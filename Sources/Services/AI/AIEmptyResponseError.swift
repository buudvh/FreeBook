import Foundation

/// Provider trả lời "thành công" nhưng không có nội dung. Là lỗi chứ không phải hoàn tất: nếu coi là hoàn
/// tất thì tin trợ lý rỗng bị màn AI ẩn đi và người dùng không thấy gì cả (lỗi thật 1.3.506 với Gemini Web
/// khi Google cắt stream sớm). Dùng chung cho mọi provider ở `AIRuntimeCoordinator.startChatStreaming`.
public struct AIEmptyResponseError: LocalizedError, Sendable, Equatable {
    public let providerName: String

    public init(providerName: String) {
        self.providerName = providerName
    }

    public var errorDescription: String? {
        "\(providerName) không trả về nội dung nào — thử lại hoặc đổi model/provider."
    }
}
