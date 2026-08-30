import SwiftUI

/// Dải chip của **mẫu** đang gõ, mượn đúng idiom thanh chữ gốc của màn Check rule
/// (`ReaderRuleTraceOverlayView.originalSentenceRowView`).
///
/// Vì sao cần nó: iOS 17 không cho SwiftUI đọc vị trí con trỏ của `TextField` (`TextSelection` là
/// iOS 18), nên nếu chỉ có bảng nút token thì token luôn bị chèn vào **cuối** mẫu. Luồng chính lại là
/// nút `+` của Check rule, nơi mẫu được điền sẵn cả cụm đang chọn (`第三十七章`) và việc cần làm là
/// **thay** `三十七` bằng `<n:1-6>` — chèn cuối vô dụng. Dải chip này cấp con trỏ và vùng chọn mà
/// không phải bọc UITextView.
///
/// Một token là **một** chip (không tách `<n:1-6>` thành 7 ký tự) nhờ
/// `QuickTranslationRuleDraftAnalyzer.segments(of:)` — cùng hàm cắt mà thanh độ dài dùng để định vị
/// token, nên không có hai cách hiểu về cùng một mẫu.
struct QuickTranslationRulePatternStripView: View {
    let segments: [QuickTranslationRuleDraftAnalyzer.Segment]
    /// Chỉ số **ký tự** trong `Array(pattern)`; `length == 0` nghĩa là con trỏ chèn, không chọn gì.
    @Binding var selectionStart: Int
    @Binding var selectionLength: Int
    let onDeleteBackward: () -> Void

    private var characterCount: Int {
        segments.last?.end ?? 0
    }

    var body: some View {
        HStack(spacing: 6) {
            if segments.isEmpty {
                Text("Mẫu đang trống — gõ chữ ở ô trên hoặc bấm một token bên dưới.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            caretTarget(at: 0)

                            ForEach(segments) { segment in
                                chip(segment)
                                caretTarget(at: segment.end)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectionStart) { _, _ in
                        withAnimation { proxy.scrollTo("pattern-caret-\(selectionStart)", anchor: .center) }
                    }
                }
            }

            Button(action: onDeleteBackward) {
                Image(systemName: "delete.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color.secondary.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(characterCount == 0 || (selectionLength == 0 && selectionStart == 0))
            .accessibilityLabel("Xoá phần đang chọn trong mẫu")
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func chip(_ segment: QuickTranslationRuleDraftAnalyzer.Segment) -> some View {
        let isSelected = selectionLength > 0
            && segment.start >= selectionStart
            && segment.end <= selectionStart + selectionLength

        return Text(segment.text)
            .font(.system(size: 15, weight: segment.kind == .literal ? .regular : .semibold,
                          design: segment.kind == .literal ? .default : .monospaced))
            .foregroundColor(color(for: segment.kind))
            .padding(.horizontal, segment.kind == .literal ? 1 : 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.28) : background(for: segment.kind))
            )
            .id("pattern-seg-\(segment.id)")
            .onTapGesture {
                selectionStart = segment.start
                selectionLength = segment.length
            }
    }

    /// Vạch chèn giữa hai chip. Bấm vào là đặt con trỏ, không chọn gì — token mới sẽ chèn tại đây.
    private func caretTarget(at index: Int) -> some View {
        let isActive = selectionLength == 0 && selectionStart == index

        return Rectangle()
            .fill(isActive ? Color.accentColor : Color.clear)
            .frame(width: 2, height: 22)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .id("pattern-caret-\(index)")
            .onTapGesture {
                selectionStart = index
                selectionLength = 0
            }
    }

    private func color(for kind: QuickTranslationRuleDraftAnalyzer.Segment.Kind) -> Color {
        switch kind {
        case .literal: return .primary
        case .token: return .accentColor
        case .groupPunct: return .orange
        }
    }

    private func background(for kind: QuickTranslationRuleDraftAnalyzer.Segment.Kind) -> Color {
        switch kind {
        case .literal: return .clear
        case .token: return Color.accentColor.opacity(0.12)
        case .groupPunct: return Color.orange.opacity(0.12)
        }
    }
}
