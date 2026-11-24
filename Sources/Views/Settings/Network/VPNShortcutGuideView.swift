import SwiftUI

/// Trang **"Cách tạo phím tắt"** của mục VPN 1.1.1.1 ở Mạng & DNS (1.3.1059, mockup
/// https://claude.ai/artifact/NqVsj9fYBpdFUJJfzeZi1k): các bước tạo phím tắt "Đặt VPN" › Bật/tắt › 1.1.1.1 trong app Phím
/// tắt, theo khuôn bước đánh số của `SystemDNSGuideView`. Nhãn tiếng Việt của iOS có thể lệch đôi chữ giữa các bản.
struct VPNShortcutGuideView: View {
    @AppStorage(VPNShortcutLauncher.shortcutNameKey) private var shortcutName = VPNShortcutLauncher.defaultShortcutName

    var body: some View {
        Form { Group {
            setupSection
            notesSection
            Section {
                Button {
                    VPNShortcutRunner.openShortcutsApp()
                } label: {
                    Label("Mở app Phím tắt", systemImage: "arrow.up.forward.app")
                }
            }
        }.glassSheetRows() }
        .backPageTitle("Tạo phím tắt VPN")
    }

    private var setupSection: some View {
        Section {
            step(1, "Cài app **1.1.1.1** của Cloudflare, bật một lần để iOS thêm cấu hình VPN.")
            step(2, "Mở app **Phím tắt** › **+** › Thêm tác vụ › tìm “VPN” › chọn **Đặt VPN**.")
            step(3, "Bấm chữ “Kết nối” đổi thành **Bật/tắt**; bấm chữ “VPN” chọn cấu hình **1.1.1.1**.")
            step(4, "Đặt tên phím tắt đúng như ô Tên phím tắt: **\(displayName)**.")
            step(5, "Chạy thử ngay trong app Phím tắt: VPN 1.1.1.1 phải bật / tắt theo. Không phản ứng thì nút trong app cũng không làm được gì.")
        } header: {
            Text("Tạo một lần")
        }
    }

    private var notesSection: some View {
        Section {
            note("Chế độ **1.1.1.1** (chỉ đổi DNS) hay **WARP** (đổi cả IP) chọn trong app 1.1.1.1; phím tắt chỉ bật / tắt.")
            note("Mỗi lần bấm, app Phím tắt hiện lên giây lát rồi tự quay về đây. Lần đầu iOS có thể hỏi cho phép mở Phím tắt.")
        } header: {
            Text("Lưu ý")
        }
    }

    private var displayName: String {
        let trimmed = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? VPNShortcutLauncher.defaultShortcutName : trimmed
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        row(Text("\(number).").monospacedDigit(), text)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        row(Text("•"), text)
    }

    private func row(_ marker: Text, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            marker
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
