import SwiftUI

/// Badge "có chương mới" cạnh một dòng truyện. Dấu chấm thay cho số khi mục lục chỉ lấy được một phần
/// (`isCountExact == false`) — thà không nói số còn hơn nói số sai.
///
/// Tách khỏi `ShelfView+NewChapters` để màn Bộ sưu tập dùng đúng một bản.
struct NewChapterBadgeView: View {
    let bookId: String

    @ObservedObject private var inbox = NewChapterInboxManager.shared

    var body: some View {
        if let record = inbox.record(for: bookId), record.hasNew {
            Text(record.badgeText)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.red))
                .accessibilityLabel(
                    record.isCountExact
                        ? "\(record.newChapterCount) chương mới"
                        : "Có chương mới"
                )
        }
    }
}
