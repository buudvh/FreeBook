import SwiftUI

/// Sheet "Nhập truyện" của Kệ sách (nút "+" nổi ở tab Kệ sách, hàng "Nhập truyện" của ngăn kéo): ba lối nhập trong một
/// panel bo góc, không vạch ngăn.
///
/// - "Từ URL" đẩy bước `ShelfImportURLStep` ngay trong sheet.
/// - Sheet chỉ **báo** lựa chọn qua `onChoose`; `ShelfView` đóng sheet rồi mới làm việc thật trong `onDismiss` (mở
///   Chi tiết / trình duyệt / bộ chọn file) — xem `ShelfView+ImportEntry`.
struct ShelfImportSheet: View {
    /// Việc người dùng chọn — `ShelfView` thực thi sau khi sheet đóng hẳn.
    enum Choice: Equatable {
        /// Mở Chi tiết truyện ở `detailUrl` qua tiện ích `packageId` (bước "Từ URL" đã dò ra).
        case openBook(detailUrl: String, packageId: String, sourceName: String)
        /// Mở trình duyệt nhập truyện; `"home"` = trang chủ trình duyệt.
        case openBrowser(urlString: String)
        case pickFile
    }

    let onChoose: (Choice) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ShelfImportURLStep(onChoose: onChoose)
                    } label: {
                        optionLabel("Từ URL", systemImage: "link")
                    }
                    .listRowSeparator(.hidden)

                    Button {
                        onChoose(.openBrowser(urlString: "home"))
                    } label: {
                        optionLabel("Mở trình duyệt", systemImage: "safari")
                    }
                    .listRowSeparator(.hidden)

                    Button {
                        onChoose(.pickFile)
                    } label: {
                        optionLabel("Từ file", systemImage: "square.and.arrow.down", detail: "txt, epub, cbz, mp4…")
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .pageTitle("Nhập truyện")
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func optionLabel(_ title: String, systemImage: String, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
    }
}
