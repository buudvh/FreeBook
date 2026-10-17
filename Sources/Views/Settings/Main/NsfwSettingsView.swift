import SwiftUI

/// Màn "Nội dung nhạy cảm (NSFW)" trong Cài đặt › Thư Viện: công tắc NSFW **toàn app** kèm giải thích.
///
/// Dùng chung khoá `RepositoryFilterPolicy.includeNsfwDefaultsKey` với công tắc NSFW trong bộ lọc Kho, nên đổi ở một
/// chỗ là chỗ kia đổi theo. Khoá về `false` mỗi lần mở app (`RepositoryFilterPolicy.resetNsfwVisibilityOnLaunch`).
struct NsfwSettingsView: View {
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    var body: some View {
        Form {
            Section {
                Toggle("Hiện nội dung nhạy cảm", isOn: $includeNsfw)
            } footer: {
                Text("Mặc định tắt. Mỗi lần mở lại app, công tắc tự tắt.")
            }

            Section(header: Text("Khi tắt")) {
                explanationRow("shippingbox", "Kho tiện ích và tìm kiếm mọi nguồn không hiện tiện ích NSFW.")
                explanationRow("safari", "Khám phá ẩn nguồn NSFW. Đang xem nguồn NSFW thì tự chuyển sang nguồn khác.")
                explanationRow("clock.arrow.circlepath", "Tab Lịch sử ẩn truyện chữ, truyện tranh và phim của nguồn NSFW. Dữ liệu vẫn giữ, bật lại là hiện lại.")
                explanationRow("books.vertical", "Sách đã thêm lên Kệ vẫn hiện bình thường.")
            }

            Section(header: Text("Nhận biết nguồn NSFW")) {
                explanationRow("tag", "Tiện ích tự khai nhạy cảm, hoặc tên, mô tả, tên miền chứa từ khoá nhạy cảm.")
                explanationRow("clock.badge.xmark", "Tiện ích NSFW mặc định không lưu lịch sử đọc/xem; đổi được trong màn cấu hình của từng tiện ích.")
            }
        }
        .navigationTitle("Nội dung nhạy cảm")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func explanationRow(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        } icon: {
            Image(systemName: symbol)
                .foregroundColor(.secondary)
        }
    }
}
