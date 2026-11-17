import Foundation

/// Chữ + tiến độ của một tác vụ tải / xuất đang chạy — dùng chung cho dòng ở màn Thông báo
/// (`NotificationInboxView.StoryTaskActivityRow`) và ô ở mục "Đang chạy" của sheet hub (`FloatingHubActivity`, 1.3.967),
/// để hai nơi nói cùng một câu.
extension DownloadTask {
    /// Tên truyện: cùng luật với toast kết quả của `DownloadManager` (ba cấp + phồn → giản).
    var activityTitle: String {
        BookDisplayTranslation.text(
            bookTitle,
            BookDisplayTranslation.listOptions(bookId: bookId, packageId: extensionPackageId)
        )
    }

    /// "Tải truyện · 12/300 chương" / "Tải video · 3/10 tập · 34%"; tác vụ xuất nối thêm giai đoạn ("Đang tạo
    /// file") khi đã có.
    var activityDetail: String {
        var parts = [displayTypeName]
        if totalCount > 0 {
            parts.append("\(progressCount)/\(totalCount) \(unitNoun)")
        }
        if let percent = videoProgressPercent {
            parts.append("\(percent)%")
        }
        if let stage = exportStage {
            parts.append(stage.displayName)
        }
        return parts.joined(separator: " · ")
    }

    /// `nil` khi chưa biết tổng số chương (mục lục chưa nạp xong) ⇒ thanh chạy vô định. Video chạy mượt theo phần
    /// trăm của tập đang tải (`smoothProgressCount`).
    var activityFraction: Double? {
        guard totalCount > 0 else { return nil }
        return min(1, smoothProgressCount / Double(totalCount))
    }
}
