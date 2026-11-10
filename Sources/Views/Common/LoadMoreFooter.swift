import SwiftUI

/// Chân của danh sách cuộn vô hạn (1.3.678): Khám phá + Thể loại (`DiscoveryNovelsLayoutView`), Tìm trong một nguồn
/// (`SearchSingleSourceResultsView`), Tất cả bình luận (`AllCommentsView`), Kệ / Lịch sử (`ShelfBooksLayoutView`).
///
/// Ba trạng thái (mockup đã duyệt): vòng xoay lúc đang nạp trang kế; "Không tải được trang kế" + "Thử lại" khi trang kế
/// lỗi hết lượt tự thử; "Đã hết · N truyện" giữa hai vạch mờ khi hết trang. Không có nút "Xem thêm" — nạp vẫn tự chạy
/// khi cuộn tới (bộ nạp của nơi dùng tự chặn gọi trùng). Nơi dùng nên tải trước vài mục trước khi tới chân (1.3.819);
/// kích hoạt ở đây là lưới an toàn.
///
/// **Hàng chân giữ id cố định** (1.3.819): nơi dùng **không** gắn `.id(số mục)` cho hàng chân nữa. Mẹo đó (1.3.679) làm
/// mỗi trang mới về thì hàng chân đang hiện bị xoá + chèn hàng id mới cùng lúc N hàng mới ⇒ `List` nạp lại cả bảng:
/// trắng xoá một nhịp, bìa dựng lại, lệch vị trí cuộn. Thay vào đó nơi dùng truyền `token` (số mục):
/// - vòng xoay mới mỗi trang bằng `.id(token)` **chỉ trên `ProgressView`** (trong hàng `List` tái dùng nó hiện trống /
///   đứng yên từ lần thứ hai);
/// - kích hoạt tải bằng `.task(id:)` theo `token` ⇒ trang về mà chân vẫn trên màn (lưới chưa đầy) tự tải tiếp.
///
/// **Không giữ state**: đừng ghi state khi chân hiện (1.3.678 ghi `UUID()` mới mỗi lần hiện ⇒ hàng cuối vẽ lại → "hiện"
/// lại → ghi tiếp, vòng lặp trên main thread làm đơ app khi cuộn tới cuối). Màu theo màu nhấn của app.
struct LoadMoreFooter: View {
    enum Phase: Equatable {
        case loading
        /// Thông báo lỗi gốc — chỉ đọc cho VoiceOver; màn hiện câu ngắn như mockup.
        case failed(String)
        /// Phần sau "Đã hết · " (vd. "128 truyện"); rỗng ⇒ chỉ "Đã hết".
        case finished(String)
    }

    let phase: Phase
    /// Số mục hiện có của danh sách: đổi ⇒ vòng xoay mới + kích hoạt tải lại nếu chân còn trên màn.
    var token = 0
    var onAppear: () -> Void = {}
    var onRetry: () -> Void = {}

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            // Chạy khi chân hiện, và chạy lại khi `token` đổi lúc chân vẫn trên màn. Không ghi state.
            .task(id: phase == .loading ? token : -1) {
                if phase == .loading { onAppear() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .id(token)
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
