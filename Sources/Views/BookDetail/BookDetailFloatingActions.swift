import SwiftUI

/// Nút "+" nổi của Chi tiết truyện — tách khỏi `BookDetailView`, vẽ theo cấu hình nút nổi ở Cài đặt › Giao diện
/// (`FloatingRoundButton`, nền kính), canh lề như nút "+" chung (16 / 12).
///
/// - Chạm "+" ⇒ **sheet hành động kiểu hub** (anh Bửu duyệt mockup 2026-11-11, thay cụm pill xổ lên của
///   `FloatingActionMenu`): dòng đầu tên truyện + "Ch. N/tổng" (truyện chưa lưu ⇒ "N chương"); các dòng Đọc ngay / Đọc
///   tiếp (kèm tên chương đang đọc), Thêm vào kệ / Đã ở kệ (icon xanh), Tải, Xuất, và **"Về trang gốc" dưới cùng** khi
///   trang đủ điều kiện Home (`FloatingHomePlacement`: trang đẩy vào trong tab Kệ / Khám phá / Tiện ích; Chi tiết mở trong
///   Reader / truyện tranh / phim thì không có). Sheet nằm trên mọi viên thuốc (`.hubStyleActionSheet`); chạm dòng ⇒ sheet
///   đóng xong mới làm việc đó.
/// - Chưa có mục lục (đang tải / lỗi) ⇒ không có nút "+"; trang đủ điều kiện thì còn nút Home tròn ở đúng chỗ đó.
/// - Đăng ký trang là `.addButton` với `FloatingHomeRegistry` ⇒ tiêu đề (`PageTitleModifier`) không vẽ Home riêng đè lên.
/// - Không đụng `@Model` / coordinator: mọi hành động là closure của `BookDetailView`.
struct BookDetailFloatingActions: View {
    /// Mục lục có ít nhất một chương ⇒ có nút "+".
    let hasChapters: Bool
    /// Tên truyện đang hiện (đã dịch theo trang) — dòng đầu sheet.
    let sheetTitle: String
    /// "Ch. N/tổng" / "N chương" bên phải tên.
    let progressCaption: String?
    let readTitle: String
    let readSystemImage: String
    /// Tên chương "Đọc tiếp" sẽ mở — chỉ đọc lúc bấm "+" (tra mục lục + dịch tên chương, không làm mỗi lượt vẽ).
    let readDetail: () -> String?
    let isOnShelf: Bool
    /// `nil` = không có dòng Tải.
    let downloadTitle: String?
    /// `nil` = không có dòng Xuất.
    let exportTitle: String?
    let onRead: () -> Void
    let onToggleShelf: () -> Void
    let onDownload: () -> Void
    let onExport: () -> Void

    @State private var actionSheet: HubStyleActionSheetContent?

    var body: some View {
        FloatingHomeReader(role: .addButton) { placement in
            ZStack(alignment: .bottomTrailing) {
                // Khung toàn trang luôn có mặt: nền của view rỗng không được dựng ⇒ đầu dò Home phải gắn lên view thật.
                Color.clear
                    .allowsHitTesting(false)
                if hasChapters {
                    FloatingRoundButton(systemImage: "plus", accessibilityLabel: "Thao tác với truyện") {
                        actionSheet = makeSheet(home: placement?.homeAction)
                    }
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
        .hubStyleActionSheet($actionSheet)
    }

    private func makeSheet(home: (@MainActor () -> Void)?) -> HubStyleActionSheetContent {
        var items: [HubStyleActionSheetContent.Item] = [
            HubStyleActionSheetContent.Item(
                id: "read",
                title: readTitle,
                detail: readDetail(),
                systemImage: readSystemImage
            ) { onRead() },
            HubStyleActionSheetContent.Item(
                id: "shelf",
                title: isOnShelf ? "Đã ở kệ" : "Thêm vào kệ",
                detail: isOnShelf ? "Chạm để bỏ khỏi kệ" : nil,
                systemImage: isOnShelf ? "checkmark.circle.fill" : "plus.circle.fill",
                tint: isOnShelf ? Color.green : nil
            ) { onToggleShelf() }
        ]
        if let downloadTitle {
            items.append(HubStyleActionSheetContent.Item(
                id: "download",
                title: downloadTitle,
                systemImage: "arrow.down.circle.fill"
            ) { onDownload() })
        }
        if let exportTitle {
            items.append(HubStyleActionSheetContent.Item(
                id: "export",
                title: exportTitle,
                systemImage: "square.and.arrow.up.fill"
            ) { onExport() })
        }
        if let home {
            items.append(HubStyleActionSheetContent.Item(
                id: "home",
                title: FloatingActionItem.homeTitle,
                systemImage: "house"
            ) { home() })
        }
        return HubStyleActionSheetContent(title: sheetTitle, caption: progressCaption, items: items)
    }
}
