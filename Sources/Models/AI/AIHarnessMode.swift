import Foundation

/// Chế độ làm việc của AI Agent Harness trong Reader.
public enum AIHarnessMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Manual / Ask: Luôn hỏi người dùng duyệt trước khi thực hiện thay đổi dữ liệu truyện.
    case ask = "ask"
    /// Plan: Lập kế hoạch chi tiết các bước, người dùng bấm Duyệt mới thực thi.
    case plan = "plan"
    /// Bypass permissions: Tự động thực hiện mọi quyền thao tác dữ liệu theo yêu cầu mà không cần hỏi.
    case bypass = "bypass"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ask: return "Manual (Ask)"
        case .plan: return "Plan"
        case .bypass: return "Bypass permissions"
        }
    }

    public var shortTitle: String {
        switch self {
        case .ask: return "Ask"
        case .plan: return "Plan"
        case .bypass: return "Bypass"
        }
    }

    public var description: String {
        switch self {
        case .ask: return "Always ask before making changes (Hỏi trước khi sửa dữ liệu)"
        case .plan: return "Create a plan before making changes (Lập kế hoạch duyệt)"
        case .bypass: return "Accepts all permissions (Tự động thực hiện mọi quyền)"
        }
    }

    public var systemIcon: String {
        switch self {
        case .ask: return "shield.fill"
        case .plan: return "list.bullet.clipboard.fill"
        case .bypass: return "bolt.fill"
        }
    }
}
