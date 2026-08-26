import SwiftUI

/// Một hàng rule trong `QuickTranslationRuleListView`, mirror đúng `DictionaryEntryRow` của từ điển:
/// icon cùng cỡ, cùng padding, thứ tự cố định `[Sửa] [Chuyển] [Tắt|Bật] [Xoá]`.
///
/// Icon **Chuyển** là COPY sang phạm vi còn lại (rule nguồn giữ nguyên), giống hệt nút Chuyển của
/// từ điển. Ở danh sách **Chung** mà không biết truyện đang mở thì icon mờ và chạm vào chỉ báo lý do,
/// tuyệt đối không ghi bừa vào đâu.
struct QuickTranslationRuleEntryRow: View {
    let rule: QuickTranslationCompiledRule
    let scope: QuickTranslationRuleScope
    /// Mẫu này đang bị tắt ở **chính** phạm vi đang xem.
    let isDisabled: Bool
    /// Rule của bộ chung đang bị tắt cho mọi truyện — hàng ở phạm vi riêng phải nói ra.
    let isDisabledGlobally: Bool
    let issues: [QuickTranslationRuleIssue]
    /// bookId của màn đang mở; `nil` = không xác định được truyện hiện tại.
    let contextBookId: String?

    let onEdit: () -> Void
    let onTransfer: (QuickTranslationRuleScope) -> Void
    let onShareToBook: () -> Void
    let onToggleDisabled: () -> Void
    let onDelete: () -> Void
    let onMissingContext: () -> Void

    private var transferTarget: QuickTranslationRuleScope? {
        QuickTranslationRuleTransfer.opposite(of: scope, contextBookId: contextBookId)
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("dòng \(rule.sourceLine)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if isDisabled {
                        badge("ĐÃ TẮT", color: .orange)
                    }
                    if isDisabledGlobally, !scope.isGlobal {
                        badge("TẮT Ở BỘ CHUNG", color: .orange)
                    }
                    if let worst = issues.min(by: { $0.severity < $1.severity }) {
                        issueBadge(for: worst, extraCount: issues.count - 1)
                    }
                    Spacer(minLength: 0)
                }

                Text(rule.pattern)
                    .font(.system(.footnote, design: .monospaced))
                Text(rule.replacement)
                    .font(.footnote)
                    .foregroundColor(.accentColor)
            }
            .opacity(isDisabled ? 0.5 : 1)

            Spacer(minLength: 8)

            actionIcons
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var actionIcons: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sửa rule dòng \(rule.sourceLine)")

            transferButton

            Button(action: onToggleDisabled) {
                Image(systemName: isDisabled ? "play.circle" : "pause.circle")
                    .foregroundColor(isDisabled ? .green : .orange)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDisabled ? "Bật rule dòng \(rule.sourceLine)" : "Tắt rule dòng \(rule.sourceLine)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xoá rule dòng \(rule.sourceLine)")
        }
    }

    @ViewBuilder
    private var transferButton: some View {
        if let target = transferTarget {
            Menu {
                Section(target.isGlobal ? "Chuyển qua Chung" : "Chuyển qua Riêng") {
                    Button {
                        onTransfer(target)
                    } label: {
                        Label(target.longLabel, systemImage: "arrow.left.arrow.right")
                    }
                }
                if !scope.isGlobal {
                    Button {
                        onShareToBook()
                    } label: {
                        Label("Chia sẻ sang truyện khác…", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                transferIcon(color: .accentColor)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Chuyển rule dòng \(rule.sourceLine) sang \(target.longLabel)")
        } else {
            Button(action: onMissingContext) {
                transferIcon(color: .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Không xác định được truyện hiện tại để chuyển rule")
        }
    }

    private func transferIcon(color: Color) -> some View {
        Image(systemName: "arrow.left.arrow.right")
            .foregroundColor(color)
            .font(.subheadline)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    @ViewBuilder
    private func issueBadge(for issue: QuickTranslationRuleIssue, extraCount: Int) -> some View {
        let color: Color = issue.severity == .disabling ? .orange : .yellow
        badge(extraCount > 0 ? "\(issue.code.rawValue) +\(extraCount)" : issue.code.rawValue, color: color)
    }
}
