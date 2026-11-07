import SwiftUI

/// Đầu phần dưới khung phim: **dòng nhãn thể loại** `#KiếmHiệp #CổTrang` (trên tên phim, kiểu trình phát dọc), tên phim,
/// dòng meta `nguồn · N tập` + "…thêm" (sheet Thông tin).
///
/// Nhãn (1.3.776): **mọi** thể loại trên **một hàng**, mỗi nhãn đủ chữ (không cắt đuôi), không đủ chỗ thì cuộn ngang — hàng
/// cuộn tràn sát hai mép màn, chữ đầu vẫn thẳng lề 16 với tên phim. Tên thể loại bỏ khoảng trắng sau dấu `#`. Thể loại có
/// script ⇒ bấm được (phim vào cửa sổ nhỏ, mở danh sách thể loại); không có script (nhãn trơn của nguồn Legado) ⇒ chỉ hiện
/// chữ.
struct VideoWatchTitleBlock: View {
    let model: VideoWatchModel
    let episodeCount: Int
    let onShowInfo: () -> Void
    let onSelectGenre: (CategoryResult) -> Void

    /// Lề ngang của khối — hàng nhãn cuộn bù lại để chạm hai mép màn.
    private static let horizontalInset: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.genres.isEmpty {
                tagRow
            }
            Text(DisplayTextFormatter.titleCase(model.meta(model.displayTitle)))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            metaRow
        }
        .padding(.horizontal, Self.horizontalInset)
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.genres) { genre in
                    if genre.script.isEmpty {
                        tagLabel(genre)
                    } else {
                        Button {
                            onSelectGenre(genre)
                        } label: {
                            tagLabel(genre)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Self.horizontalInset)
        }
        .padding(.horizontal, -Self.horizontalInset)
    }

    private func tagLabel(_ genre: CategoryResult) -> some View {
        Text("#" + Self.tagText(model.meta(genre.title)))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .fixedSize()
    }

    /// "Kiếm hiệp" ⇒ "KiếmHiệp": viết hoa đầu mỗi từ rồi bỏ khoảng trắng (kiểu hashtag).
    static func tagText(_ title: String) -> String {
        title
            .split(whereSeparator: { $0.isWhitespace })
            .map { word in String(word.prefix(1)).uppercased() + String(word.dropFirst()) }
            .joined()
    }

    /// `nguồn · N tập` + "…thêm" (mở sheet Thông tin: bìa, tác giả, thể loại, giới thiệu đầy đủ).
    private var metaRow: some View {
        Button(action: onShowInfo) {
            HStack(spacing: 4) {
                Text(metaText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("…thêm")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .layoutPriority(1)
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.65))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(metaText). Xem thêm thông tin phim")
    }

    private var metaText: String {
        var parts: [String] = []
        if !model.request.sourceName.isEmpty { parts.append(model.request.sourceName) }
        if episodeCount > 0 { parts.append("\(episodeCount) tập") }
        if !model.author.isEmpty { parts.append(model.meta(model.author)) }
        return parts.joined(separator: " · ")
    }
}
