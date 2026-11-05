import SwiftUI

/// Sheet **Thông tin** của màn xem ("…thêm" / chạm khối Giới thiệu): bìa, tên, tác giả, nguồn, số tập, đủ chip thể loại
/// và giới thiệu đầy đủ (mô tả + phần `detail` của chi tiết). Bấm chip thể loại có script ⇒ `onSelectGenre` (màn cha đóng
/// sheet rồi mới thu nhỏ phim, mở danh sách thể loại). Vuốt xuống để đóng.
struct VideoWatchInfoSheet: View {
    let model: VideoWatchModel
    let episodeCount: Int
    let onSelectGenre: (CategoryResult) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !model.genres.isEmpty {
                    section("Thể loại") {
                        FlowLayout(spacing: 8) {
                            ForEach(model.genres) { genre in
                                genreChip(genre)
                            }
                        }
                    }
                }
                if !fullDescription.isEmpty {
                    section("Giới thiệu") {
                        Text(model.meta(fullDescription))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .padding(.top, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Đầu sheet

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            cover
            VStack(alignment: .leading, spacing: 6) {
                Text(DisplayTextFormatter.titleCase(model.meta(model.displayTitle)))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.author.isEmpty {
                    infoRow("person", model.meta(model.author))
                }
                if !model.request.sourceName.isEmpty {
                    infoRow("globe", model.request.sourceName)
                }
                if episodeCount > 0 {
                    infoRow("film.stack", "\(episodeCount) tập")
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var cover: some View {
        let packageId = model.request.packageId
        let url = CoverRequestResolver.displayURL(model.coverUrl, itemHost: model.host, packageId: packageId)
        RemoteCoverImage(
            url: url,
            referer: CoverRequestResolver.referer(itemHost: model.host, packageId: packageId),
            contentMode: .fill,
            placeholderSymbol: "film"
        )
        .frame(width: 96, height: 136)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private func infoRow(_ systemImage: String, _ text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(2)
    }

    // MARK: - Khối

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            content()
        }
    }

    @ViewBuilder
    private func genreChip(_ genre: CategoryResult) -> some View {
        let label = Text(model.meta(genre.title))
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Thể loại không kèm script (vd `kind` của nguồn Legado) chỉ là nhãn — không có danh sách để mở.
        if genre.script.isEmpty {
            label
        } else {
            Button {
                onSelectGenre(genre)
            } label: {
                label
            }
            .buttonStyle(.plain)
        }
    }

    /// Mô tả + phần `detail` (đã bỏ HTML), như giới thiệu lưu vào `Book` (`savedDesc`).
    private var fullDescription: String {
        let desc = model.desc.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = model.detail.cleanHTML().trimmingCharacters(in: .whitespacesAndNewlines)
        if extra.isEmpty { return desc }
        if desc.isEmpty { return extra }
        return "\(desc)\n\n\(extra)"
    }
}
