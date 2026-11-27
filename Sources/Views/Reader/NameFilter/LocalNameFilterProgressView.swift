import SwiftUI

/// Màn "Đang lọc" của sheet "Lọc name local" (mockup khung 3): "Đọc chương X / N" + thanh tiến độ, rồi danh sách name
/// hiện dần — bộ lọc chụp lại sau mỗi khối chương, lần sau cách lần trước ít nhất gấp đôi thời gian lần trước nên truyện
/// dài cập nhật thưa dần. Name vừa vào có vạch + nhãn "mới", name vừa rơi ra gạch mờ — cả hai chỉ một nhịp (tới lần cập
/// nhật kế, `LocalNameFilterLiveRow`). Danh sách chỉ để xem; chọn / loại ở màn duyệt. Nút "Dừng" nằm ở thanh đáy của sheet.
struct LocalNameFilterProgressView: View {
    let session: LocalNameFilterSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(Text("Đang lọc"))
                progressCard

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    sectionTitle(Text("Name đã thấy (\(session.liveNameCount))"))
                    Spacer(minLength: 8)
                    Text(updateCaption)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 10)

                // `LazyVStack`: truyện dài có thể vài trăm name, chỉ dựng hàng đang hiện.
                LazyVStack(spacing: 6) {
                    ForEach(session.liveRows) { row in
                        liveRow(row)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.25), value: session.updateGeneration)
        }
    }

    private var progressTitle: String {
        switch session.phase {
        case .preparing: return "Đang lấy danh sách chương…"
        case .stopping: return "Đang phân tích phần đã đọc…"
        default: return "Đọc chương"
        }
    }

    private var updateCaption: String {
        if session.phase == .stopping { return "sắp xong…" }
        guard let chapter = session.lastUpdateChapter else { return "chờ lần cập nhật đầu…" }
        // Số chương **đã đọc trong lượt lọc**, không phải số thứ tự chương (lọc từ giữa truyện vẫn đếm từ 1).
        return "cập nhật sau \(chapter) chương"
    }

    private var progressCard: some View {
        let total = session.totalChapters
        let read = min(session.chaptersRead, total)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(progressTitle)
                Spacer(minLength: 8)
                if total > 0 {
                    Text("\(read) / \(total)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            ProgressView(value: Double(read), total: Double(max(total, 1)))
        }
        .padding(16)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionTitle(_ text: Text) -> some View {
        text
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }

    private func liveRow(_ row: LocalNameFilterLiveRow) -> some View {
        HStack(spacing: 0) {
            // Vạch "mới" bên trái — chỉ một nhịp.
            Rectangle()
                .fill(row.mark == .fresh ? Color.accentColor : Color.clear)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.term)
                        .font(.headline)
                        .strikethrough(row.mark == .gone)
                        .lineLimit(1)

                    if row.mark == .gone {
                        Text("bị loại khi đọc thêm")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        kindBadge(row.kindLabel)
                        Text("\(row.count) lần")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize()
                        if row.mark == .fresh {
                            freshBadge
                        }
                    }
                }

                if row.mark != .gone {
                    Text(row.meaning)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Spacer(minLength: 0)
        }
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(row.mark == .gone ? 0.35 : 1)
        .accessibilityElement(children: .combine)
    }

    /// Cùng kiểu badge loại của màn duyệt (`ReaderAINameReviewCardView`).
    private func kindBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(white: 0.25))
            .foregroundColor(.white)
            .cornerRadius(4)
            .fixedSize()
    }

    /// Kiểu chip đang chọn của app (chữ màu nhấn, nền nhấn mờ, viền nhấn) — không tô nền nhấn đặc (luật `WHITE_TINT_FILL`).
    private var freshBadge: some View {
        Text("mới")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.accentColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor.opacity(0.6), lineWidth: 0.8))
            .fixedSize()
    }
}
