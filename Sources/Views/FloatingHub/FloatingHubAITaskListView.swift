import SwiftUI

/// Trang "Tác vụ AI" trong thẻ menu của nút hub nổi (1.3.558): mỗi truyện đang chạy AI một dòng — tên truyện và
/// tác vụ ("AI đang suy nghĩ", "Đang quét: Batch N/T"), truyện bắt đầu gần nhất lên đầu. Từ 1.3.630 thêm truyện có
/// kết quả chưa xem bên dưới (✓ xanh "Đã xong — bấm để xem", ! đỏ "Lỗi — bấm để xem"). Chạm dòng nào thì mở màn AI
/// của đúng truyện đó; nút ‹ quay về trang chính của menu.
///
/// Cùng khung dòng với `FloatingHubMenuRow` (icon 28pt, hai dòng chữ, cao tối thiểu 48pt) để hai trang trông như một.
struct FloatingHubAITaskListView: View {
    let tasks: [FloatingHubPresentationReader.AITask]
    let onSelect: (String) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(tasks) { task in
                row(task)
            }
        }
    }

    /// Nút quay lại theo chuẩn header (icon 17pt semibold, vùng chạm 38×44pt) + tiêu đề trang.
    private var header: some View {
        HStack(spacing: 2) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Quay lại"))

            Text("Tác vụ AI")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
    }

    private func row(_ task: FloatingHubPresentationReader.AITask) -> some View {
        Button(action: { onSelect(task.bookId) }) {
            HStack(spacing: 12) {
                Image(systemName: iconName(task))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(task.isRunning ? AnyShapeStyle(FloatingHubItem.Kind.ai.tint) : task.detailTone.style)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.bookTitle.isEmpty ? "Truyện không tên" : task.bookTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(task.detailText)
                        .font(.system(size: 12))
                        .foregroundStyle(task.detailTone.style)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
            // Lề dọc nằm **trong** vùng chạm để cả chiều cao dòng (48pt) đều bấm được.
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Mở Trợ lý AI của truyện này"))
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .overlay(alignment: .top) {
            Divider()
                .padding(.leading, 52)
        }
    }

    private func iconName(_ task: FloatingHubPresentationReader.AITask) -> String {
        switch task.outcome {
        case nil:
            return FloatingHubItem.Kind.ai.systemImage(unreadCount: 0)
        case .finished:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }
}
