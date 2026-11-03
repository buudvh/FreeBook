import SwiftUI

/// Nút nguồn ở đầu header Khám phá: nút tròn 38 chứa icon tiện ích đang chọn, bên cạnh là tên và link nguồn trên hai
/// dòng (dài thì "…"). Cả nút tròn lẫn vùng chữ đều mở ngăn kéo chọn nguồn.
struct DiscoverySourceHeaderButton: View {
    let ext: Extension?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if let ext {
                        ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 24)
                    } else {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .frame(width: 38, height: 38)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(ext?.name ?? "Chọn nguồn")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let sourceUrl = ext?.sourceUrl, !sourceUrl.isEmpty {
                        Text(sourceUrl)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ext.map { "Nguồn \($0.name), chọn nguồn khác" } ?? "Chọn nguồn")
    }
}
