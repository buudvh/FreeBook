import SwiftUI

/// Một hàng giọng của sheet chọn giọng VieNeu (1.3.899).
///
/// - Nút tròn bên trái: ▶ thử giọng; ■ khi đang thử (tổng hợp / phát) **hoặc** đang tải (bấm = huỷ); ⬇ khi thiếu dữ liệu.
/// - Thân hàng: tên + dòng phụ (thông tin, " · cần tải N MB" khi chưa tải; đang tải ⇒ "Đang tải 37% · 93 / 251 MB" +
///   thanh mảnh), ✓ nếu là giọng đang chọn, badge Nhẹ / Vừa / Nặng. Chạm thân hàng = chọn giọng — chỉ khi đã tải đủ.
///
/// Hàng chỉ vẽ; trạng thái do sheet tính sẵn và truyền vào.
struct VieNeuVoiceListRow: View {
    let entry: VieNeuVoiceEntry
    let isSelected: Bool
    let isReady: Bool
    let missingBytes: Int64
    /// Lượt tải đang chạy / đang chờ của đích tải ứng với giọng này.
    let download: ModelDownloadCenter.Entry?
    let isPreviewing: Bool
    let onPrimary: () -> Void
    let onSelect: () -> Void

    private var isDownloading: Bool { download?.state.isRunning ?? false }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrimary) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(isReady || isDownloading ? 0.18 : 0.10))
                    Image(systemName: primarySymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(primaryLabel)

            Button(action: onSelect) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name)
                            .font(.body)
                            .foregroundColor(isReady ? .primary : .secondary)
                            .lineLimit(1)
                        detailView
                    }
                    Spacer(minLength: 6)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    VieNeuVoiceWeightBadge(weight: entry.weight)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isReady)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var detailView: some View {
        if let download, download.state.isRunning {
            VStack(alignment: .leading, spacing: 4) {
                Text(VieNeuSizeFormatter.progress(download))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                if let fraction = download.fraction, !download.isQueued {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                }
            }
        } else if let text = detailText {
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var detailText: String? {
        var parts: [String] = []
        if let detail = entry.detail { parts.append(detail) }
        if !isReady { parts.append("cần tải \(VieNeuSizeFormatter.megabytes(missingBytes))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var primarySymbol: String {
        if isDownloading || isPreviewing { return "stop.fill" }
        return isReady ? "play.fill" : "arrow.down"
    }

    private var primaryLabel: String {
        if isDownloading { return "Huỷ tải \(entry.name)" }
        if isPreviewing { return "Dừng thử giọng \(entry.name)" }
        return isReady ? "Thử giọng \(entry.name)" : "Tải giọng \(entry.name)"
    }
}
