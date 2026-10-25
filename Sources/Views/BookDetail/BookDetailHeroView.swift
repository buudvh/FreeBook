import SwiftUI

/// Khối đầu tab Chi tiết: nền là bìa làm mờ nhạt dần về nền màn, bìa lớn ở giữa, tên truyện, chip tác giả và chip
/// nguồn (icon tiện ích + tên miền).
///
/// Bìa dọc hay ngang theo **tỉ lệ thật của ảnh** (`BookCoverView.onImageSize` — thumbnail giữ tỉ lệ gốc): ảnh rộng
/// hơn cao từ `landscapeThreshold` thì dựng ngang gần hết bề ngang màn, còn lại dựng dọc 150×210. Lúc ảnh chưa về thì
/// đoán theo loại nguồn (`prefersLandscapeCover` — video) để khung ít nhảy.
///
/// Cả hai lớp bìa đều là `BookCoverView` theo `bookId` (cùng file `covers/`, `ImageCacheManager` gộp lượt tải trùng).
/// Lớp nền dựng thumbnail nhỏ rồi phóng: đã làm mờ thì không cần ảnh to.
struct BookDetailHeroView: View {
    let bookId: String
    let coverUrl: String
    let extensionPackageId: String
    /// Tên đã dịch + in hoa đầu từ.
    let title: String
    /// Tác giả đã dịch + in hoa đầu từ; rỗng ⇒ không có chip tác giả.
    let author: String
    /// Host của sách (`BookDetailView.resolvedHost`) — chip nguồn hiện tên miền của nó.
    let sourceHost: String?
    /// Tên tiện ích — chip nguồn dùng khi không suy ra được tên miền.
    let sourceName: String
    let localPath: String
    let iconUrl: String?
    let prefersLandscapeCover: Bool

    /// Rộng : cao của ảnh bìa đã tải; `nil` khi chưa có ảnh.
    @State private var imageAspect: CGFloat?

    private static let portraitAspect: CGFloat = 5.0 / 7.0
    private static let portraitWidth: CGFloat = 150
    private static let landscapeGuessAspect: CGFloat = 16.0 / 9.0
    /// Ảnh gần vuông vẫn dựng dọc; từ tỉ lệ này mới là bìa ngang.
    private static let landscapeThreshold: CGFloat = 1.15
    private static let landscapeMaxAspect: CGFloat = 2.4
    private static let landscapeMaxWidth: CGFloat = 420
    /// Cỡ thumbnail của lớp nền trước khi phóng.
    private static let backdropSize = CGSize(width: 40, height: 56)

    var body: some View {
        VStack(spacing: 12) {
            cover
                .padding(.horizontal, 16)

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            if !author.isEmpty {
                chip {
                    Image(systemName: "person")
                    Text(author)
                }
            }

            chip {
                if !localPath.isEmpty {
                    ExtensionIconView(localPath: localPath, iconUrl: iconUrl ?? "", size: 16)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                }
                Text(sourceLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background { backdrop }
        .onChange(of: bookId) { _, _ in
            imageAspect = nil
        }
    }

    // MARK: - Bìa

    private var coverAspect: CGFloat {
        guard let imageAspect else {
            return prefersLandscapeCover ? Self.landscapeGuessAspect : Self.portraitAspect
        }
        guard imageAspect >= Self.landscapeThreshold else { return Self.portraitAspect }
        return min(imageAspect, Self.landscapeMaxAspect)
    }

    private var cover: some View {
        let aspect = coverAspect
        let isLandscape = aspect > 1
        return Color(.secondarySystemBackground)
            .aspectRatio(aspect, contentMode: .fit)
            .frame(width: isLandscape ? nil : Self.portraitWidth)
            .frame(maxWidth: isLandscape ? Self.landscapeMaxWidth : nil)
            .overlay {
                GeometryReader { proxy in
                    // Lượt layout đầu có thể báo cỡ 0 — dựng `BookCoverView` ở 0×0 là thêm một lượt giải mã vô ích.
                    if proxy.size.width > 1, proxy.size.height > 1 {
                        BookCoverView(
                            bookId: bookId,
                            coverUrl: coverUrl,
                            width: proxy.size.width,
                            height: proxy.size.height,
                            extensionPackageId: extensionPackageId,
                            onImageSize: updateImageAspect
                        )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    /// Đổi khung bìa thì thumbnail dựng lại ở cỡ mới và báo lại tỉ lệ (lệch vài phần nghìn do làm tròn pixel) — bỏ qua
    /// chênh nhỏ để không vẽ lại vòng quanh.
    private func updateImageAspect(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let aspect = size.width / size.height
        if let current = imageAspect, abs(current - aspect) < 0.02 { return }
        imageAspect = aspect
    }

    // MARK: - Nền

    private var backdrop: some View {
        GeometryReader { proxy in
            if proxy.size.width > 1, proxy.size.height > 1 {
                BookCoverView(
                    bookId: bookId,
                    coverUrl: coverUrl,
                    width: Self.backdropSize.width,
                    height: Self.backdropSize.height,
                    extensionPackageId: extensionPackageId
                )
                // Làm mờ ở cỡ thumbnail **rồi** mới phóng: `scaleEffect` không đổi khung layout (vẫn 40×56), làm mờ
                // sau khi phóng có thể chỉ phủ đúng khung nhỏ đó ở góc trên-trái.
                .blur(radius: 3, opaque: true)
                .scaleEffect(
                    x: proxy.size.width / Self.backdropSize.width,
                    y: proxy.size.height / Self.backdropSize.height,
                    anchor: .topLeading
                )
            }
        }
        // Phủ màu nền cho chữ đọc được trên mọi bìa, rồi nhạt dần về đúng màu nền ở đáy để nối liền phần thẻ.
        .overlay { Color(.systemBackground).opacity(0.4) }
        .overlay {
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .clipped()
        .allowsHitTesting(false)
    }

    // MARK: - Chip

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
        .padding(.horizontal, 20)
    }

    /// Tên miền của host sách (bỏ `www.`); không suy ra được thì tên tiện ích.
    private var sourceLabel: String {
        guard var value = ExtensionHostResolver.nonEmpty(sourceHost) else { return sourceName }
        if !value.contains("://") {
            value = "https://" + value
        }
        return BrowserSitePreferenceStore.normalizedDomain(for: URL(string: value)?.host) ?? sourceName
    }
}
