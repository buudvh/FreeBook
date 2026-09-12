import SwiftUI

/// Một chip rule trong dải của màn Check rule.
///
/// Tương tác: **bấm** = chọn rule đó (thanh gốc tô lại cụm, thanh nghĩa đổi theo); **ấn giữ** = mở
/// popup Bật / Tắt / Xoá. Ấn giữ dùng `simultaneousGesture` như `dictSegmentButton` của màn Dịch để
/// không tranh chấp với `Button` bên dưới.
struct ReaderRuleTraceChip: View {
    let trace: QuickTranslationRuleTrace
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    private var style: ReaderRuleChipStyle {
        ReaderRuleChipStyle(status: trace.status)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(trace.scope.label)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(style.textColor.opacity(0.18))
                        .cornerRadius(3)

                    Text(trace.pattern)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .lineLimit(1)

                    if let mark = style.trailingMark {
                        Text(mark)
                            .font(.system(size: 11, weight: .heavy))
                    }
                }

                Text(ReaderRuleChipStyle.label(for: trace.status))
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .opacity(0.85)
            }
            .foregroundColor(style.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.12, green: 0.12, blue: 0.15))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(style.borderColor, lineWidth: style.borderWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(isSelected ? 0.55 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onLongPress()
            }
        )
        .accessibilityLabel("Rule \(trace.pattern), phạm vi \(trace.scope.label), \(ReaderRuleChipStyle.label(for: trace.status))")
        .accessibilityHint("Nhấn để xem cụm áp dụng, nhấn giữ để sửa, bật, tắt hoặc xoá")
    }
}
