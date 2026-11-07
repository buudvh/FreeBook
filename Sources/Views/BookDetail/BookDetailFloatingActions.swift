import SwiftUI

/// Nút "+" nổi của Chi tiết truyện — tách khỏi `BookDetailView`, vẽ theo cấu hình nút nổi ở Cài đặt › Giao diện
/// (`FloatingActionMenu`: nút tròn + pill nền kính, không còn nền xám đặc), canh lề như nút "+" chung (16 / 12).
///
/// - Pill từ trên xuống: Đọc / Đọc tiếp, Thêm vào kệ (đã ở kệ ⇒ viền + icon xanh thay cho nền xanh đặc), Tải, Xuất,
///   và **"Về trang gốc" dưới cùng** khi trang đủ điều kiện Home (`FloatingHomePlacement`: trang đẩy vào trong tab Kệ /
///   Khám phá / Tiện ích; Chi tiết mở trong Reader / truyện tranh / phim thì không có).
/// - Chưa có mục lục (đang tải / lỗi) ⇒ không có nút "+"; trang đủ điều kiện thì còn nút Home tròn ở đúng chỗ đó.
/// - Đăng ký trang là `.addButton` với `FloatingHomeRegistry` ⇒ tiêu đề (`PageTitleModifier`) không vẽ Home riêng đè lên.
/// - Không đụng `@Model` / coordinator: mọi hành động là closure của `BookDetailView`.
struct BookDetailFloatingActions: View {
    /// Mục lục có ít nhất một chương ⇒ có nút "+".
    let hasChapters: Bool
    let readTitle: String
    let readSystemImage: String
    let isOnShelf: Bool
    /// `nil` = không có pill Tải.
    let downloadTitle: String?
    /// `nil` = không có pill Xuất.
    let exportTitle: String?
    let onRead: () -> Void
    let onToggleShelf: () -> Void
    let onDownload: () -> Void
    let onExport: () -> Void

    var body: some View {
        FloatingHomeReader(role: .addButton) { placement in
            ZStack(alignment: .bottomTrailing) {
                // Khung toàn trang luôn có mặt: nền của view rỗng không được dựng ⇒ đầu dò Home phải gắn lên view thật.
                Color.clear
                    .allowsHitTesting(false)
                if hasChapters {
                    FloatingActionMenu(accessibilityLabel: "Thao tác với truyện", items: items(home: placement?.homeAction))
                        .padding(.trailing, FloatingRoundButton.trailingInset)
                        .padding(.bottom, FloatingRoundButton.bottomInset)
                } else if let home = placement?.homeAction {
                    FloatingRoundButton(systemImage: "house", accessibilityLabel: FloatingActionItem.homeTitle) {
                        home()
                    }
                    .padding(.trailing, FloatingRoundButton.trailingInset)
                    .padding(.bottom, FloatingRoundButton.bottomInset)
                }
            }
        }
    }

    private func items(home: (@MainActor () -> Void)?) -> [FloatingActionItem] {
        var result: [FloatingActionItem] = [
            FloatingActionItem(id: "read", title: readTitle, systemImage: readSystemImage) { onRead() },
            FloatingActionItem(
                id: "shelf",
                title: isOnShelf ? "Đã ở kệ" : "Thêm vào kệ",
                systemImage: isOnShelf ? "checkmark.circle.fill" : "plus.circle.fill",
                highlight: isOnShelf ? Color.green : nil
            ) { onToggleShelf() }
        ]
        if let downloadTitle {
            result.append(FloatingActionItem(id: "download", title: downloadTitle, systemImage: "arrow.down.circle.fill") {
                onDownload()
            })
        }
        if let exportTitle {
            result.append(FloatingActionItem(id: "export", title: exportTitle, systemImage: "square.and.arrow.up.fill") {
                onExport()
            })
        }
        if let home {
            result.append(.home(home))
        }
        return result
    }
}
