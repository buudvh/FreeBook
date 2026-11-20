import SwiftUI

/// Khối tiêu đề **hai dòng** của header màn đọc / xem / nghe (1.3.1017): dòng 1 tên truyện / phim / bài 16pt nửa đậm,
/// dòng 2 chương / tập / nguồn 13pt màu phụ; mỗi dòng một dòng, dài thì cắt đuôi. Trước đây mỗi màn một kiểu (Reader 16
/// đậm / 13, truyện tranh 11 / 15 đảo thứ tự, phim 15 / 12, màn nghe 11 / 15 căn giữa).
///
/// ```swift
/// HeaderTitleBlock(title: book.title, subtitle: chapterTitle)
/// HeaderTitleBlock(title: track.title, subtitle: "Từ playlist \(name)", alignment: .center)
/// ```
struct HeaderTitleBlock: View {
    let title: String
    var subtitle: String? = nil
    var alignment: HorizontalAlignment = .leading
    /// Nền đọc Sáng / Trầm ấm ⇒ truyền màu chữ của nền thay cho mặc định.
    var titleColor: Color = .primary
    var subtitleColor: Color = .secondary

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.system(size: HeaderMetrics.infoTitleFontSize, weight: .semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: HeaderMetrics.infoSubtitleFontSize))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .accessibilityElement(children: .combine)
    }
}
