import Foundation

/// Bộ gán nhãn LAC đã nạp xong (lấy từ `LACModel.prepare`).
///
/// Hợp đồng giữa model (`NER/`) và bộ lọc (`Engine/`):
/// - `tag(_:)` nhận **một dòng** (không có `\n`), trả các từ theo thứ tự, nối lại đúng bằng dòng vào. Dòng rỗng ⇒ `[]`.
/// - **An toàn đa luồng**: bộ lọc gọi song song từ nhiều luồng nền cho nhiều chương cùng lúc; không giữ trạng thái đổi
///   được giữa các lần gọi (bộ đệm tạm cấp theo từng lần gọi).
/// - Kết quả trùng `LAC(mode="lac").run(dòng)` của LAC 2.1.2 Python, trừ vài câu lệch do embedding fp16 / thứ tự cộng.
protocol LACTagging: Sendable {
    func tag(_ line: String) -> [LACToken]
}
