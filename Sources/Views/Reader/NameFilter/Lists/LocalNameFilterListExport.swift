import Foundation

/// "Xuất file" ở ngăn kéo `…` của các màn danh sách Lọc name local — **Hậu tố**, **Tiền tố**, **Không phải name** (anh Bửu
/// 2026-11-28: "thêm chức năng xuất danh sách tiền tố hậu tố và lọc rác tôi gửi cho điều tra"). Xuất **đúng danh sách của
/// chip phạm vi đang chọn** (Chung hoặc Riêng truyện), không theo ô tìm / chip loại, cùng định dạng file gốc để đọc lại được:
/// - hậu tố / tiền tố: `chữ Hán=nghĩa|loại|vị trí` như `NameFilterSuffixes.txt` / `NameFilterPrefixes.txt`;
/// - Không phải name: mỗi dòng một cụm.
/// Dòng đầu là chú thích `#` (danh sách, phạm vi, số mục, giờ xuất). Ghi vào thư mục tạm rồi đưa bảng chia sẻ hệ thống.
/// "Nhập file" của cùng ba màn đọc lại đúng định dạng này (`LocalNameFilterListImport`) — đổi dạng dòng thì đổi cả hai bên.
enum LocalNameFilterListExport {
    /// File đang đưa cho bảng chia sẻ (`.sheet(item:)` của màn danh sách).
    struct File: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    /// Nội dung file của danh sách hậu tố / tiền tố.
    static func affixContent(_ entries: [LocalNameFilterSuffixEntry], listName: String, isBookScope: Bool) -> String {
        let lines = entries.map { "\($0.key)=\($0.meaning)|\($0.kind.rawValue)|\($0.position.rawValue)" }
        return header(listName: listName, isBookScope: isBookScope, count: lines.count) + lines.joined(separator: "\n") + "\n"
    }

    /// Nội dung file của danh sách "Không phải name".
    static func termContent(_ terms: [String], listName: String, isBookScope: Bool) -> String {
        header(listName: listName, isBookScope: isBookScope, count: terms.count) + terms.joined(separator: "\n") + "\n"
    }

    /// Ghi `content` vào thư mục tạm dưới tên `<fileStem>_<Chung|RiengTruyen>_<yyyyMMddHHmmss>.txt`.
    static func write(_ content: String, fileStem: String, isBookScope: Bool, date: Date = Date()) throws -> File {
        let name = "\(fileStem)_\(isBookScope ? "RiengTruyen" : "Chung")_\(timestamp(date)).txt"
        return File(url: try DictionaryExportFileName.writeTemporaryFile(content, named: name))
    }

    private static func header(listName: String, isBookScope: Bool, count: Int) -> String {
        "# \(listName) · \(isBookScope ? "Riêng truyện" : "Chung") · \(count) mục · xuất \(timestamp(Date()))\n"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date)
    }
}
