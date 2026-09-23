import Foundation

/// Hành động thao tác dữ liệu do AI Agent Harness đề xuất hoặc thực thi.
public struct AIHarnessAction: Identifiable, Codable, Sendable, Equatable {
    public enum ActionType: String, Codable, Sendable {
        case addCustomName
        case addVietPhraseEntry
        case addJunkFilter
        case deleteCustomEntry
    }

    public enum ActionStatus: String, Codable, Sendable {
        case pendingReview
        case approved
        case rejected
        case executed
        case failed
    }

    public let id: UUID
    public let type: ActionType
    public var title: String
    public var detail: String
    public var payload: [String: String]
    public var status: ActionStatus

    public init(
        id: UUID = UUID(),
        type: ActionType,
        title: String,
        detail: String,
        payload: [String: String],
        status: ActionStatus = .pendingReview
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.payload = payload
        self.status = status
    }
}
