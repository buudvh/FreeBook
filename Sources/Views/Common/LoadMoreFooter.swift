import SwiftUI

/// Chân của danh sách cuộn vô hạn (1.3.678): Khám phá + Thể loại (`DiscoveryNovelsLayoutView`), Tìm trong một nguồn
/// (`SearchSingleSourceResultsView`), Tất cả bình luận (`AllCommentsView`), Kệ / Lịch sử (`ShelfBooksLayoutView`).
///
/// Ba trạng thái (mockup đã duyệt): vòng xoay lúc đang nạp trang kế; "Không tải được trang kế" + "Thử lại" khi trang kế
/// lỗi hết lượt tự thử; "Đã hết · N truyện" giữa hai vạch mờ khi hết trang. Không có nút "Xem thêm" — nạp vẫn tự chạy
/// khi cuộn tới (bộ nạp của nơi dùng tự chặn gọi trùng; `onAppear` ở đây chỉ là lưới an toàn).
///
/// **Không giữ state** (1.3.679): `ProgressView` trong hàng `List` bị tái dùng hiện trống / đứng yên từ lần thứ hai, nên
/// nơi dùng gắn `.id(số mục)` cho chân ⇒ mỗi trang mới về là một vòng xoay mới. Đừng ghi state trong `onAppear` ở đây
/// (1.3.678 ghi `UUID()` mới mỗi lần hiện ⇒ hàng cuối vẽ lại → "hiện" lại → ghi tiếp, vòng lặp trên main thread làm đơ
/// app khi cuộn tới cuối). Màu theo màu nhấn của app.
struct LoadMoreFooter: View {
    enum Phase: Equatable {
        case loading
        /// Thông báo lỗi gốc — chỉ đọc cho VoiceOver; màn hiện câu ngắn như mockup.
        case failed(String)
        /// Phần sau "Đã hết · " (vd. "128 truyện"); rỗng ⇒ chỉ "Đã hết".
        case finished(String)
    }

    let phase: Phase
    var onAppear: () -> Void = {}
    var onRetry: () -> Void = {}

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .onAppear {
                if phase == .loading { onAppear() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(height: 44)
                .accessibilityLabel("Đang tải thêm")
        case .failed(let message):
            VStack(spacing: 6) {
                Text("Không tải được trang kế")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button(action: onRetry) {
                    Label("Thử lại", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityHint(message)
        case .finished(let caption):
            HStack(spacing: 10) {
                divider
                Text(caption.isEmpty ? "Đã hết" : "Đã hết · \(caption)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                divider
            }
            .frame(height: 44)
            .padding(.horizontal, 8)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 1)
    }
}
