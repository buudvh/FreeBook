import SwiftUI

/// Trang **"Cách tạo phím tắt"** của mục VPN 1.1.1.1 ở Mạng & DNS (1.3.1059; hai phím tắt Bật / Tắt 1.3.1061, mockup bản 3
/// https://claude.ai/artifact/NqVsj9fYBpdFUJJfzeZi1k): bước tạo phím tắt bật ("Đặt VPN" › Kết nối) và phím tắt tắt
/// ("Đặt VPN" › Ngắt kết nối) trong app Phím tắt, theo khuôn bước đánh số của `SystemDNSGuideView`, cộng mục "VPN tự bật
/// lại". Nhãn tiếng Việt của iOS có thể lệch đôi chữ giữa các bản.
struct VPNShortcutGuideView: View {
    @AppStorage(VPNShortcutLauncher.Action.on.nameKey) private var onName = VPNShortcutLauncher.Action.on.defaultName
    @AppStorage(VPNShortcutLauncher.Action.off.nameKey) private var offName = VPNShortcutLauncher.Action.off.defaultName

    var body: some View {
        Form { Group {
            onSection
            offSection
            reconnectSection
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

    private var onSection: some View {
        Section {
            step(1, "App **Phím tắt** › **+** › Thêm tác vụ › tìm “VPN” › **Đặt VPN**.")
            step(2, "Giữ **Kết nối**; bấm chữ “VPN” chọn cấu hình **1.1.1.1** (cài app 1.1.1.1 và bật một lần để iOS có cấu hình này).")
            step(3, "Đặt tên **\(displayName(onName, .on))**.")
        } header: {
            Text("Phím tắt bật")
        }
    }

    private var offSection: some View {
        Section {
            step(1, "Tạo phím tắt mới, thêm **Đặt VPN** như trên.")
            step(2, "Bấm chữ “Kết nối” đổi thành **Ngắt kết nối**; chọn **1.1.1.1**.")
            step(3, "Đặt tên **\(displayName(offName, .off))**.")
        } header: {
            Text("Phím tắt tắt")
        }
    }

    private var reconnectSection: some View {
        Section {
            note("Xem dòng **App chạy phím tắt lần cuối** ở Mạng & DNS: giờ ở đó cũ hơn lúc VPN bật thì không phải app này bật.")
            note("Thử tắt mục **Kết nối theo yêu cầu** ở Cài đặt › Cài đặt chung › VPN & Quản lý thiết bị › VPN › (i) cạnh 1.1.1.1, hoặc tắt VPN bằng công tắc lớn trong app 1.1.1.1.")
        } header: {
            Text("VPN tự bật lại")
        }
    }

    private func displayName(_ saved: String, _ action: VPNShortcutLauncher.Action) -> String {
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? action.defaultName : trimmed
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
