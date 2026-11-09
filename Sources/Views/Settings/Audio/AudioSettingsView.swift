import SwiftUI

/// Màn **Âm thanh** (Cài đặt › Đọc & Nghe › Âm thanh) — cài đặt của trình nghe âm thanh (tiện ích loại `audio`), cùng kiểu
/// `VideoSettingsView`:
/// - Nhóm **Khi hết bài**: "Tự phát bài gợi ý" (`AudioAutoNextPolicy`, cùng khoá với công tắc trong ngăn kéo `…` của màn
///   nghe).
///
/// Giá trị đọc/ghi bằng `@AppStorage` trên đúng khoá tầng nền đọc — đổi là có hiệu lực từ lần hết bài kế tiếp.
struct AudioSettingsView: View {
    /// Mặc định bật — khớp `AudioAutoNextPolicy.isEnabled` (khoá chưa ghi = bật).
    @AppStorage(AudioAutoNextPolicy.defaultsKey) private var autoNextSuggest = AudioAutoNextPolicy.defaultValue

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $autoNextSuggest) {
                    Label("Tự phát bài gợi ý", systemImage: "forward.end.circle")
                }
            } header: {
                SectionHelpHeader("Khi hết bài", paragraphs: [
                    "**Tự phát bài gợi ý**: nghe hết bài lẻ, hoặc hết album khi đang tắt lặp, thì phát ngay mục đầu tiên của nhóm gợi ý đầu tiên của nguồn: bài lẻ sang bài gợi ý, playlist sang playlist liên quan. Chạy cả khi màn nghe đã thu nhỏ, ở màn khoá hay khi app chạy nền.",
                    "Mục đã phát trong cùng một chuỗi tự phát bị bỏ qua để không lặp qua lại. Mỗi mục tự phát được lưu vào Lịch sử như khi tự mở. Đang lặp album hoặc lặp một bài thì album không bao giờ hết nên không tự phát."
                ])
            }
        }
        .backPageTitle("Âm thanh")
    }
}
