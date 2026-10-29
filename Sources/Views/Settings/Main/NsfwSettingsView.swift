import SwiftUI

/// Màn "Nội dung nhạy cảm (NSFW)" trong Cài đặt › Thư Viện: công tắc NSFW **toàn app** kèm giải thích, và tuỳ chọn
/// "Tắt tiếng khi mở phim" (`VideoMutePolicy`, chuyển từ Cài đặt › Đọc & Nghe sang đây).
///
/// Dùng chung khoá `RepositoryFilterPolicy.includeNsfwDefaultsKey` với công tắc NSFW trong bộ lọc Kho, nên đổi ở một
/// chỗ là chỗ kia đổi theo. Khoá về `false` mỗi lần mở app (`RepositoryFilterPolicy.resetNsfwVisibilityOnLaunch`).
struct NsfwSettingsView: View {
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false
    /// Cùng khoá `VideoMutePolicy` đọc lúc mở phim mới; mặc định `nsfwOnly`.
    @AppStorage(VideoMutePolicy.defaultsKey) private var videoMutePolicy: VideoMutePolicy = VideoMutePolicy.defaultValue

    var body: some View {
        Form {
            Section {
                Toggle("Hiện nội dung nhạy cảm", isOn: $includeNsfw)
            } header: {
                SectionHelpHeader("Hiển thị", paragraphs: ["Mặc định tắt. Mỗi lần mở lại app, công tắc tự tắt. Cũng bật/tắt nhanh ở bảng chọn nguồn của Khám phá."])
            }

            Section {
                Picker(selection: $videoMutePolicy) {
                    ForEach(VideoMutePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                } label: {
                    Label("Tắt tiếng khi mở phim", systemImage: "speaker.slash")
                }
                .pickerStyle(.navigationLink)
            }

            Section(header: Text("Khi tắt")) {
                explanationRow("shippingbox", "Kho tiện ích và tìm kiếm mọi nguồn không hiện tiện ích NSFW.")
                explanationRow("safari", "Khám phá ẩn nguồn NSFW. Đang xem nguồn NSFW thì tự chuyển sang nguồn khác.")
                explanationRow("clock.arrow.circlepath", "Tab Lịch sử ẩn truyện chữ, truyện tranh và phim của nguồn NSFW. Dữ liệu vẫn giữ, bật lại là hiện lại.")
                explanationRow("books.vertical", "Kệ sách, Tìm trong Kệ, Bộ sưu tập, tab Tải, hub nổi (Tác vụ AI, Video) và Quản lý phạm vi dịch ẩn truyện, truyện tranh, phim của nguồn NSFW. Dữ liệu vẫn giữ, bật lại là hiện lại.")
                explanationRow("doc.text", "Danh sách chọn truyện để chia sẻ/nhập từ điển riêng ẩn mọi truyện của nguồn NSFW, kể cả truyện trên Kệ.")
                explanationRow("globe", "Trình duyệt: Truy cập nhanh không hiện nguồn NSFW, lịch sử duyệt trang của chúng bị ẩn (không xoá).")
                explanationRow("xmark.rectangle", "Màn Chi tiết truyện, danh sách thể loại và tìm trong một nguồn NSFW đang mở (kể cả ở tab khác, kể cả truyện trên Kệ) tự đóng. Tìm mọi nguồn thì ẩn nhóm kết quả của nguồn NSFW.")
            }

            Section(header: Text("Nhận biết nguồn NSFW")) {
                explanationRow("tag", "Tiện ích tự khai nhạy cảm, hoặc tên, mô tả, tên miền chứa từ khoá nhạy cảm.")
                explanationRow("clock.badge.xmark", "Tiện ích NSFW mặc định không lưu lịch sử đọc/xem; đổi được trong màn cấu hình của từng tiện ích.")
                explanationRow("eye.slash", "Vào trang của nguồn không lưu lịch sử, tab trình duyệt tự ẩn danh: không ghi lịch sử duyệt, cookie và đăng nhập vẫn giữ. Về Home là hết ẩn danh.")
            }
        }
        .backPageTitle("Nội dung nhạy cảm")
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
