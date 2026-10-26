import Foundation

/// Một chương đã tải trong sheet chọn phạm vi quét tên riêng (1.3.602): chỉ số + tên hiển thị, nạp **một lần** khi mở
/// sheet (`AIBookDataInspector.nameScanChapters`) — mọi con số của sheet tính trên RAM từ danh sách này.
struct AINameScanChapter: Sendable, Identifiable, Equatable {
    /// Chỉ số 0-based theo mục lục.
    let index: Int
    /// `title` đã trim, rỗng thì `titleTrans`; có thể rỗng.
    let title: String

    var id: Int { index }

    /// Số chương hiển thị — đánh từ 1 như mọi chỗ khác trong app.
    var number: Int { index + 1 }

    /// "ch.N: tên", tên rỗng thì chỉ "ch.N".
    var label: String {
        title.isEmpty ? "ch.\(number)" : "ch.\(number): \(title)"
    }
}
