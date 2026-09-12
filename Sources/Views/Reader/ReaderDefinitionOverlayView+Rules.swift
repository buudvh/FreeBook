import SwiftUI

/// Hai hàng của Check rule sau khi gộp vào panel Dịch (1.3.334): **ô nghĩa rule chỉ đọc** và **dải chip
/// rule** có nút `+` ở đầu.
///
/// Vì sao ô nghĩa rule là một ô riêng chứ không dùng ô nghĩa dịch: hai thứ trả lời hai câu hỏi khác
/// nhau — ô nghĩa dịch là chỗ người dùng **gõ** định nghĩa để lưu, ô nghĩa rule chỉ **hiện** chuỗi mà
/// rule sinh ra. Nhồi vào cùng một ô là mỗi lần bấm chip lại xoá chữ người dùng đang gõ.
extension ReaderDefinitionOverlayView {

    /// Rule đang chọn; chưa chọn gì thì lấy rule đầu dải để ô nghĩa không trống trơn.
    internal var focusedRuleTrace: QuickTranslationRuleTrace? {
        if let focusedRuleTraceID, let match = ruleTraces.first(where: { $0.id == focusedRuleTraceID }) {
            return match
        }
        return ruleTraces.first
    }

    /// Cụm mà rule đang chọn áp vào, để hàng câu gốc tô một lớp riêng — **không** đụng vùng chọn của
    /// người dùng. Đây là điểm khác duy nhất so với màn Check rule cũ (ở đó bấm chip là snap vùng chọn).
    internal var focusedRuleRange: NSRange? {
        guard let trace = focusedRuleTrace, trace.sourceRange.length > 0 else { return nil }
        return trace.sourceRange
    }

    // MARK: - Ô nghĩa rule (chỉ đọc)

    @ViewBuilder
    internal var ruleMeaningRowView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Nghĩa rule")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isEInkEnabled ? paper : Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                    .overlay { if isEInkEnabled { RoundedRectangle(cornerRadius: 3).strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }

                if let trace = focusedRuleTrace {
                    Text(ReaderRuleChipStyle.label(for: trace.status))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if let header = ruleNoticeHeader {
                    Text(header)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .einkAccentForeground(.orange)
                }

                Spacer()

                if isLoadingRules {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            Group {
                if let trace = focusedRuleTrace {
                    Text(trace.rendered.isEmpty ? "(rule này không sinh chữ nào ở đây)" : trace.rendered)
                        .font(.subheadline)
                        .foregroundColor(trace.status.isDisabled ? .secondary : .primary)
                } else {
                    Text(ruleNoticeContent)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .lineLimit(1)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .leading)
        .background(isEInkEnabled ? paper : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay { if isEInkEnabled { RoundedRectangle(cornerRadius: 8).strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
    }

    private var ruleNoticeHeader: String? {
        if !hasAnyRuleSet { return "Chưa có rule" }
        if !isRuleFeatureEnabled { return "Đang tắt" }
        if ruleTraces.isEmpty { return isLoadingRules ? "Đang tải…" : "Không khớp" }
        return nil
    }

    private var ruleNoticeContent: String {
        if !hasAnyRuleSet {
            return "Máy chưa có bộ rule nào (Cài đặt → Quản lý rule dịch)."
        }
        if !isRuleFeatureEnabled {
            return "Công tắc rule dịch đang TẮT trong Cài đặt."
        }
        if ruleTraces.isEmpty {
            return isLoadingRules ? "Đang cập nhật rule cho đoạn này…" : "Không rule nào chạm đoạn này."
        }
        return ""
    }

    // MARK: - Dải chip rule

    @ViewBuilder
    internal var ruleChipRowView: some View {
        HStack(spacing: 8) {
            Button(action: onAddRule) {
                Image(systemName: "plus")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .einkAccentForeground(.green)
                    .padding(8)
                    .background(isEInkEnabled ? paper : Color.green.opacity(0.12), in: Circle())
                    .overlay { if isEInkEnabled { Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
            }
            .accessibilityLabel("Thêm rule cho cụm đang chọn")

            if ruleTraces.isEmpty {
                Text(isLoadingRules ? "Đang cập nhật…" : "Chưa có rule nào khớp")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ruleTraces) { trace in
                            ReaderRuleTraceChip(
                                trace: trace,
                                isSelected: focusedRuleTrace?.id == trace.id,
                                onTap: { focusedRuleTraceID = trace.id },
                                onLongPress: {
                                    ruleActionTarget = trace
                                    showingRuleActions = true
                                }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
    }

    // MARK: - Popup thao tác trên một rule

    /// Ba mức phạm vi tắt/bật giữ nguyên như màn Check rule cũ: rule riêng chỉ tắt được cho truyện này,
    /// rule chung tắt được cho truyện này **hoặc** cho mọi truyện.
    @ViewBuilder
    internal func ruleActionButtons(for trace: QuickTranslationRuleTrace) -> some View {
        let bookScope = QuickTranslationRuleScope.book(bookId)
        let disabledForBook = QuickTranslationRuleDisableStore.shared.isDisabled(pattern: trace.pattern, in: bookScope)

        Button("Sửa rule") {
            onRuleAction(trace, .edit)
        }

        if !bookId.isEmpty {
            Button(disabledForBook ? "Bật cho truyện này" : "Tắt cho truyện này") {
                onRuleAction(trace, .setDisabled(!disabledForBook, bookScope))
            }
        }

        if trace.scope.isGlobal {
            let disabledGlobally = QuickTranslationRuleDisableStore.shared.isDisabled(pattern: trace.pattern, in: .global)
            Button(disabledGlobally ? "Bật cho mọi truyện" : "Tắt cho mọi truyện") {
                onRuleAction(trace, .setDisabled(!disabledGlobally, .global))
            }
        }

        if let destination = QuickTranslationRuleTransfer.opposite(of: trace.scope, contextBookId: bookId) {
            Button("Chuyển sang \(destination.longLabel.lowercased())") {
                onRuleAction(trace, .moveScope(destination))
            }
        }

        Button("Xoá rule khỏi \(trace.scope.longLabel.lowercased())", role: .destructive) {
            onRuleAction(trace, .delete)
        }

        Button("Hủy", role: .cancel) {}
    }
}
