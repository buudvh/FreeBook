import SwiftUI

/// Thẻ hiển thị Kế hoạch hành động hoặc Yêu cầu phê duyệt từ AI Agent Harness.
public struct ReaderAIActionPlanCardView: View {
    public let actions: [AIHarnessAction]
    public let mode: AIHarnessMode
    public let onApprove: (AIHarnessAction) -> Void
    public let onReject: (AIHarnessAction) -> Void
    public let onApproveAll: () -> Void

    public init(
        actions: [AIHarnessAction],
        mode: AIHarnessMode,
        onApprove: @escaping (AIHarnessAction) -> Void,
        onReject: @escaping (AIHarnessAction) -> Void,
        onApproveAll: @escaping () -> Void
    ) {
        self.actions = actions
        self.mode = mode
        self.onApprove = onApprove
        self.onReject = onReject
        self.onApproveAll = onApproveAll
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: mode.systemIcon)
                    .foregroundColor(headerColor)
                Text(headerTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(headerColor)
                Spacer()
            }

            // Danh sách các hành động
            VStack(alignment: .leading, spacing: 6) {
                ForEach(actions) { action in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: iconForStatus(action.status))
                            .foregroundColor(colorForStatus(action.status))
                            .font(.system(size: 12))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.system(size: 12, weight: .semibold))
                            if !action.detail.isEmpty {
                                Text(action.detail)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if mode == .ask && action.status == .pendingReview {
                            HStack(spacing: 4) {
                                Button("Đồng ý") {
                                    onApprove(action)
                                }
                                .font(.system(size: 11, weight: .bold))
                                .buttonStyle(.borderedProminent)
                                .tint(.green)

                                Button("Bỏ") {
                                    onReject(action)
                                }
                                .font(.system(size: 11))
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Nút duyệt toàn bộ (trong Plan mode)
            if mode == .plan && hasPendingActions {
                Button(action: onApproveAll) {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                        Text("Duyệt & Thực thi toàn bộ kế hoạch")
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .padding(12)
        .background(cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(headerColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var hasPendingActions: Bool {
        actions.contains { $0.status == .pendingReview }
    }

    private var headerTitle: String {
        switch mode {
        case .ask: return "Yêu cầu phê duyệt hành động"
        case .plan: return "Kế hoạch hành động đề xuất"
        case .bypass: return "Đã tự động thực thi"
        }
    }

    private var headerColor: Color {
        switch mode {
        case .ask: return .orange
        case .plan: return .purple
        case .bypass: return .green
        }
    }

    private var cardBackground: Color {
        headerColor.opacity(0.08)
    }

    private func iconForStatus(_ status: AIHarnessAction.ActionStatus) -> String {
        switch status {
        case .pendingReview: return "hourglass"
        case .approved, .executed: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func colorForStatus(_ status: AIHarnessAction.ActionStatus) -> Color {
        switch status {
        case .pendingReview: return .orange
        case .approved, .executed: return .green
        case .rejected: return .secondary
        case .failed: return .red
        }
    }
}
