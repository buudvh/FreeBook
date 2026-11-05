import SwiftUI

/// Header của sheet Hẹn giờ TTS (`TTSQuickTimerSheet`) — cùng số đo với header sheet mục lục Reader
/// (`ReaderChapterListView.header`): bìa 86×120 bo 6, cách cột chữ 12; tên `.headline` 2 dòng, tác giả `.subheadline`
/// mờ 72%, viên nguồn `.caption2`; cột chữ cao tối thiểu bằng bìa.
///
/// - Đồng hồ hẹn giờ đè lên đáy bìa bằng `CoverCaptionStrip` (cùng dải chữ của kiểu "Chỉ bìa" ở Kệ), căn giữa, chữ số
///   rộng đều. Chưa hẹn giờ thì bìa trơn.
/// - Nút "Hủy" hẹn giờ ở góc dưới phải cột chữ (chỗ hàng nút của header Reader), chỉ hiện khi đang hẹn giờ.
/// - Không có nút ⚙ ở đây: sheet đặt nút tròn ở dải thanh kéo phía trên (`TTSQuickTimerSheet.settingsButton`) để tên
///   truyện dùng hết bề ngang. Lề trên do sheet quyết định.
struct TTSQuickTimerHeader: View {
    let bookId: String
    let coverUrl: String
    let extensionPackageId: String
    let title: String
    let author: String
    let sourceName: String
    /// Thư mục tiện ích nguồn đã cài (icon ở viên nguồn); rỗng ⇒ icon mảnh ghép.
    let sourceLocalPath: String
    let sourceIconUrl: String?
    let timerMode: TTSManager.SleepTimerMode
    /// `TTSManager.sleepTimerBadgeText` — "m:ss" khi đang đếm (kể cả lúc tạm dừng), rỗng khi chưa bắt đầu đếm.
    let timerBadgeText: String
    let onOpenReader: () -> Void
    let onCancelTimer: () -> Void

    static let coverWidth: CGFloat = 86
    static let coverHeight: CGFloat = 120

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpenReader) {
                BookCoverView(
                    bookId: bookId,
                    coverUrl: coverUrl,
                    width: Self.coverWidth,
                    height: Self.coverHeight,
                    extensionPackageId: extensionPackageId
                )
                // Dải đặt **trước** `clipShape` để nền chuyển tràn lên bị cắt theo bìa (xem `CoverCaptionStrip`).
                .overlay(alignment: .bottom) { timerCaption }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mở truyện đang đọc")

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundColor(Color.primary.opacity(0.72))
                        .lineLimit(1)
                }

                sourceBadge

                Spacer(minLength: 0)

                if timerMode != .off {
                    HStack {
                        Spacer(minLength: 0)
                        Button(action: onCancelTimer) {
                            Text("Hủy")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.red.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hủy hẹn giờ tắt")
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.coverHeight, alignment: .topLeading)
        }
        // Cột chữ có `Spacer` dọc (đẩy nút Hủy xuống đáy bìa): không cố định chiều cao thì header tham chiều cao.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// Bìa nhỏ (120pt) ⇒ phần chuyển thấp (`compactFadeHeight`), không thì dải che gần hết bìa.
    @ViewBuilder
    private var timerCaption: some View {
        switch timerMode {
        case .off:
            EmptyView()
        case .minutes(let minutes):
            CoverCaptionStrip(
                title: timerBadgeText.isEmpty ? "\(minutes) phút" : timerBadgeText,
                subtitle: "Hẹn giờ tắt",
                titleLineLimit: 1,
                fadeHeight: CoverCaptionStrip.compactFadeHeight,
                isCentered: true,
                usesMonospacedDigits: true
            )
        case .endOfChapter:
            CoverCaptionStrip(
                title: "Hết chương",
                subtitle: "Hẹn giờ tắt",
                titleLineLimit: 1,
                fadeHeight: CoverCaptionStrip.compactFadeHeight,
                isCentered: true
            )
        }
    }

    /// Viên nguồn như header Reader: icon tiện ích 14pt + tên, `.caption2` nửa đậm trên nền xám 12%.
    @ViewBuilder
    private var sourceBadge: some View {
        if !sourceName.isEmpty {
            HStack(spacing: 4) {
                if sourceLocalPath.isEmpty {
                    Image(systemName: "puzzlepiece.extension")
                        .resizable()
                        .frame(width: 12, height: 12)
                        .foregroundColor(.secondary)
                } else {
                    ExtensionIconView(localPath: sourceLocalPath, iconUrl: sourceIconUrl ?? "", size: 14)
                }
                Text(sourceName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }
}
