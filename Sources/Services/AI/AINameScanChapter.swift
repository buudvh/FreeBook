import Foundation

/// Một chương đã tải trong sheet chọn phạm vi quét tên riêng (1.3.602): chỉ số + tên hiển thị, nạp **một lần** khi mở
/// sheet (`AIBookDataInspector.nameScanChapters`) — mọi con số của sheet tính trên RAM từ danh sách này.
struct AINameScanChapter: Sendable, Identifiable, Equatable {
    /// Chỉ số 0-based theo mục lục.
    let index: Int
    /// Tên hiển thị: đã dịch theo cấu hình dịch của Reader khi bật (1.3.603), không thì bằng `rawTitle`; có thể rỗng.
    let title: String
    /// Tên gốc (`title` đã trim, rỗng thì `titleTrans`) — ô tìm của "Chọn chương…" khớp cả tên gốc lẫn tên dịch.
    let rawTitle: String
    /// Chương đã có trong máy — màn chọn hiện icon "đã tải" (1.3.627). Chỉ sheet tải/xuất đặt cờ này; sheet quét tên
    /// vốn chỉ liệt kê chương đã tải nên để mặc định `false`, không hiện icon thừa.
    var isCached: Bool = false

    var id: Int { index }

    /// Số chương hiển thị — đánh từ 1 như mọi chỗ khác trong app.
    var number: Int { index + 1 }

    /// "ch.N: tên", tên rỗng thì chỉ "ch.N".
    var label: String {
        title.isEmpty ? "ch.\(number)" : "ch.\(number): \(title)"
    }
}
