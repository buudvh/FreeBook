import SwiftUI

/// Sheet hỏi khi bấm nút tai nghe của Reader mà TTS **đang phát đúng chương** nút sắp đọc (anh Bửu). Trước đây nút dừng
/// phiên rồi đọc lại từ đoạn trên cùng màn hình ⇒ bấm nhầm là mất chỗ đang nghe.
///
/// Khuôn `TTSQuickControlSheet`: cao vừa nội dung (chiều cao đo được giữ ở **chỗ gọi** vì nội dung sheet dựng lại mỗi lần
/// mở), vuốt xuống để đóng (không nút Huỷ — luật sheet của repo), nền kính ngăn kéo `DrawerGlassSheetBackground` ⇒ nội
/// dung vẽ ở `colorScheme` tối. Neo `.blocker` ẩn đĩa nghe góc dưới trong lúc sheet mở (không neo thì đĩa đứng đè lên
/// hàng cuối). Sheet chỉ trình bày; việc của từng lựa chọn ở `ReaderView+TTSSameChapterPrompt`.
struct ReaderTTSSameChapterSheet: View {
    /// Chụp lúc bấm nút: trong lúc sheet mở TTS vẫn đọc và trang vẫn tự cuộn, nên lúc chọn không đọc lại vị trí màn hình.
    struct Prompt: Identifiable {
        let id = UUID()
        let chapterIndex: Int
        /// Đoạn trên cùng màn hình lúc bấm — ID dòng **thưa** (không phải chỉ số mảng); -1 = đầu chương.
        let viewingParagraphIndex: Int
        let bookId: String
        let bookTitle: String
        let chapterTitle: String
        let coverUrl: String
        /// TTS đọc tên chương ở đầu (`showChapterTitle_<bookId>`) ⇒ "Đọc lại từ đầu chương" bắt đầu từ tên chương.
        let readsChapterTitle: Bool
    }

    enum Choice {
        case continueCurrent
        case fromViewingParagraph
        case fromChapterStart
    }

    let prompt: Prompt
    /// TTS còn đang phát (đĩa bìa xoay, nhãn "Đang đọc"); tạm dừng giữa lúc sheet mở ⇒ "Tạm dừng".
    let isPlaying: Bool
    @Binding var height: CGFloat
    let onChoose: (Choice) -> Void

    @StateObject private var coverLoader = TTSCoverImageLoader()

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 12)
            .environment(\.colorScheme, .dark)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(HeightKey.self) { newHeight in
                guard newHeight > 0, abs(newHeight - height) > 0.5 else { return }
                height = newHeight
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .mediaDiscAnchor(.blocker)
            .appAccentTint()
            .presentationDetents(height > 0 ? [.height(height)] : [.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(16)
            .presentationBackground { DrawerGlassSheetBackground() }
            .onAppear {
                coverLoader.load(bookId: prompt.bookId, coverURL: prompt.coverUrl)
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            headerRow
            VStack(spacing: 8) {
                choiceRow(
                    .continueCurrent,
                    title: "Đọc tiếp chỗ đang đọc",
                    detail: "Cuộn về đoạn đang đọc",
                    systemImage: "play.fill",
                    isPrimary: true
                )
                choiceRow(
                    .fromViewingParagraph,
                    title: "Đọc từ đoạn đang xem",
                    detail: "Đoạn trên cùng màn hình",
                    systemImage: "eye"
                )
                choiceRow(
                    .fromChapterStart,
                    title: "Đọc lại từ đầu chương",
                    detail: prompt.readsChapterTitle ? "Bắt đầu từ tên chương" : "Bắt đầu từ đoạn đầu tiên",
                    systemImage: "arrow.counterclockwise"
                )
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Hàng đầu

    /// Đĩa bìa (góc xoay chung `TTSWidgetCoverRotation` với widget TTS) · tên truyện + tên chương · nhãn trạng thái.
    private var headerRow: some View {
        HStack(spacing: 12) {
            TTSCoverView(
                image: coverLoader.image,
                size: 52,
                rotationState: TTSWidgetCoverRotation.shared.state,
                isRotating: isPlaying
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(prompt.bookTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(prompt.chapterTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            statusBadge
        }
        .accessibilityElement(children: .combine)
    }

    /// Chip kiểu `ExtensionKindFilterBar`: chữ màu nhấn, nền nhấn mờ 18%, viền 60% — không tô nền đặc màu nhấn.
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(isPlaying ? "Đang đọc" : "Tạm dừng")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 0.5))
        .fixedSize()
    }

    // MARK: - Lựa chọn

    /// Hàng panel bo 12, nền theo màu chữ mờ (như viên của `TTSQuickControlSheet`); lựa chọn an toàn nhất có icon màu nhấn.
    private func choiceRow(
        _ choice: Choice,
        title: String,
        detail: String,
        systemImage: String,
        isPrimary: Bool = false
    ) -> some View {
        Button {
            onChoose(choice)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isPrimary ? Color.accentColor : Color.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    // MARK: - Lồng (một type chính mỗi file)

    private struct HeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}
