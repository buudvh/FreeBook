import Foundation

/// Nguồn trả lời **tải khi bấm** của một bình luận: khoá `reply_source: {input, script}` (khoá riêng của Tàng Công Các,
/// hợp đồng chỉ có mảng `replies` lồng sẵn). App gọi `script` với `(input, page)` như script bình luận — kết quả là
/// danh sách trả lời cùng dạng bình luận, `Response.success(items, next)` để tải thêm.
public struct CommentReplySource: Hashable {
    public let input: String
    public let script: String

    public init(input: String, script: String) {
        self.input = input
        self.script = script
    }
}
