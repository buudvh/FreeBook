import SwiftUI

/// Một hàng giọng của sheet chọn giọng chung (Siri / NghiTTS / Google / tiện ích) — cùng dáng `VieNeuVoiceListRow`.
///
/// - Nút tròn 36 pt bên trái: ▶ thử giọng; ■ khi đang thử; ⬇ khi chưa tải; vòng xoay khi đang tải mà không huỷ được
///   (NghiTTS — `ModelDownloadCenter` không huỷ được đích này).
/// - Thân hàng: tên + dòng phụ (hoặc chữ tiến độ + thanh mảnh khi đang tải), ✓ nếu là giọng đang chọn, badge. Chạm thân
///   hàng = chọn giọng — chỉ khi giọng dùng được ngay (`isReady`).
///
/// Hàng chỉ vẽ; trạng thái do danh sách tính sẵn và truyền vào.
struct TTSVoiceListRow: View {
    enum Primary: Equatable {
        case play
        case stop
        case download
        /// Đang tải, không huỷ được ⇒ vòng xoay, nút tắt.
        case downloading
    }

    struct Progress: Equatable {
        let text: String
        /// `nil` ⇒ thanh vô định.
        let fraction: Double?
    }

    let name: String
    let detail: String?
    var progress: Progress?
    let isReady: Bool
    let isSelected: Bool
    let primary: Primary
    let badge: TTSVoiceBadge
    let onPrimary: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrimary) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(isReady || primary == .downloading ? 0.18 : 0.10))
                    if primary == .downloading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.accentColor)
                    } else {
                        Image(systemName: primarySymbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .disabled(primary == .downloading)
            .accessibilityLabel(primaryLabel)

            Button(action: onSelect) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
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
                    badge
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
        if let progress {
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                }
            }
        } else if let detail, !detail.isEmpty {
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var primarySymbol: String {
        switch primary {
        case .play: return "play.fill"
        case .stop: return "stop.fill"
        case .download, .downloading: return "arrow.down"
        }
    }

    private var primaryLabel: String {
        switch primary {
        case .play: return "Thử giọng \(name)"
        case .stop: return "Dừng thử giọng \(name)"
        case .download: return "Tải giọng \(name)"
        case .downloading: return "Đang tải giọng \(name)"
        }
    }
}
