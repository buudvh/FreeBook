import SwiftUI

/// Trang hướng dẫn **đổi DNS / IP cho cả iPhone** (Cài đặt › Chung › Mạng & DNS, 1.3.825). DNS mã hoá trong app chỉ phủ
/// `URLSession`; trình duyệt (WebKit) và trình phát phim/nhạc (AVPlayer) chỉ đổi được bằng cài đặt của cả máy. Chỉ dẫn
/// tới nguồn chính chủ: app 1.1.1.1 của Cloudflare (App Store) và trang Public DNS của AdGuard (có profile cho iOS).
///
/// Mục cuối là cách đổi **IP** khi trang nguồn chặn theo IP: chế độ WARP của app 1.1.1.1 (anh chọn thay cho proxy
/// trong app). WARP không qua được trang chỉ cho IP nước khác.
struct SystemDNSGuideView: View {
    @Environment(\.openURL) private var openURL

    private static let cloudflareAppURL = URL(string: "https://apps.apple.com/app/id1423538627")!
    private static let adguardPublicDNSURL = URL(string: "https://adguard-dns.io/en/public-dns.html")!

    var body: some View {
        Form { Group {
            cloudflareSection
            adguardSection
            ipBlockSection
        }.glassSheetRows() }
        .backPageTitle("Đổi DNS cho cả iPhone")
    }

    // MARK: - Cách 1: app 1.1.1.1

    private var cloudflareSection: some View {
        Section {
            step(1, "Cài app **1.1.1.1** của Cloudflare (miễn phí) từ App Store.")
            step(2, "Trong cài đặt của app, chọn chế độ **1.1.1.1** (chỉ đổi DNS), không phải WARP.")
            step(3, "Bật công tắc lớn; iOS hỏi thêm cấu hình VPN thì cho phép.")
            Button {
                openURL(Self.cloudflareAppURL)
            } label: {
                Label("Mở App Store: 1.1.1.1", systemImage: "arrow.up.forward.app")
            }
        } header: {
            Text("Cách 1 · App 1.1.1.1 (dễ nhất)")
        }
    }

    // MARK: - Cách 2: profile AdGuard DNS

    private var adguardSection: some View {
        Section {
            step(1, "Mở trang AdGuard DNS bằng **Safari** — trình duyệt khác không cài được profile.")
            step(2, "Ở mục iOS chọn máy chủ **Non-filtering** (không chặn quảng cáo) hoặc **Default** (có chặn quảng cáo), bấm **Download configuration profile** rồi cho phép tải.")
            step(3, "Mở Cài đặt của iPhone › **Đã tải về hồ sơ** › Cài đặt.")
            step(4, "Muốn gỡ: Cài đặt › Cài đặt chung › **VPN & Quản lý thiết bị**.")
            Button {
                openURL(Self.adguardPublicDNSURL)
            } label: {
                Label("Mở trang AdGuard DNS", systemImage: "safari")
            }
        } header: {
            Text("Cách 2 · Profile DNS (không cần cài app)")
        }
    }

    // MARK: - Bị chặn IP

    private var ipBlockSection: some View {
        Section {
            step(1, "Trang nguồn báo lỗi 403 / 429 hoặc hỏi captcha sau khi tải nhiều chương là đang chặn **IP**, đổi DNS không giúp được.")
            step(2, "Trong app **1.1.1.1** (Cách 1) chuyển sang chế độ **WARP** ⇒ mọi kết nối của máy ra bằng IP của Cloudflare.")
            step(3, "WARP không qua được trang chỉ cho IP nước khác (IP vẫn tính là Việt Nam), và vài trang dùng Cloudflare sẽ hỏi captcha nhiều hơn.")
            step(4, "Mẹo nhanh khi dùng 4G: bật rồi tắt chế độ máy bay để nhà mạng cấp IP mới.")
        } header: {
            Text("Bị trang nguồn chặn IP")
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
