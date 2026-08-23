import Foundation

/// Một chương đã sẵn sàng ghi vào file xuất: nội dung đã lấy xong (cache hoặc vừa tải), đã dịch nếu
/// người dùng chọn dịch. `ordinal` là số thứ tự **trong bản xuất** (1-based), không phải chỉ mục
/// chương trong truyện — bản xuất có thể bắt đầu từ chương đang đọc.
public struct ExportChapterPayload: Sendable {
    public let ordinal: Int
    public let title: String
    public let content: String

    public init(ordinal: Int, title: String, content: String) {
        self.ordinal = ordinal
        self.title = title
        self.content = content
    }
}
