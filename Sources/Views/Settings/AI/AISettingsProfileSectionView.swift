import SwiftUI

/// Section hiển thị danh sách các Provider Profile đã lưu trong Cài đặt AI.
public struct AISettingsProfileSectionView: View {
    public let profiles: [AIProviderProfile]
    public let activeProfileId: String
    public let onSelectProfile: (String) -> Void
    public let onAddProfile: () -> Void

    public init(
        profiles: [AIProviderProfile],
        activeProfileId: String,
        onSelectProfile: @escaping (String) -> Void,
        onAddProfile: @escaping () -> Void
    ) {
        self.profiles = profiles
        self.activeProfileId = activeProfileId
        self.onSelectProfile = onSelectProfile
        self.onAddProfile = onAddProfile
    }

    public var body: some View {
        Section(header: Text("Danh Sách Profile Đã Lưu (\(profiles.count))")) {
            if profiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Chưa có cấu hình AI nào.")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("Bấm nút dấu cộng (+) ở góc trên bên phải để thêm cấu hình AI (Gemini, OpenAI, DeepSeek, Claude...).")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: onAddProfile) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Thêm Cấu Hình Mới")
                        }
                        .font(.footnote.bold())
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(profiles) { profile in
                    Button(action: { onSelectProfile(profile.id) }) {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(profile.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)

                                    if profile.isCustom {
                                        Text("Tự thêm")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15))
                                            .foregroundColor(.blue)
                                            .cornerRadius(4)
                                    }

                                    if profile.id == activeProfileId {
                                        Text("Đang chọn")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.2))
                                            .foregroundColor(.purple)
                                            .cornerRadius(4)
                                    }
                                }

                                Text("\(profile.baseURL) • \(profile.selectedModel.isEmpty ? "Chưa có model" : profile.selectedModel)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if profile.id == activeProfileId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.purple)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
