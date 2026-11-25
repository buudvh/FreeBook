import SwiftUI

/// Màn **Mạng & DNS** (Cài đặt › Chung, 1.3.825; mặc định tắt + bật riêng từng nguồn từ 1.3.828, 1.3.831).
/// 1. DNS mã hoá — công tắc **"Bật cho cả app"** (`EncryptedDNSPolicy`, mặc định tắt), máy chủ dùng chung cho cả bật
///    chung lẫn bật riêng, dòng **"Bật riêng: N tiện ích / nguồn"** (cờ `Extension.encryptedDNSEnabled` đặt ở Cấu hình
///    tiện ích / Chi tiết nguồn Legado), trạng thái + "Kiểm tra lại" khi có ai cần (`EncryptedDNSRepository`).
/// 2. VPN 1.1.1.1 (1.3.1059; hai phím tắt Bật / Tắt 1.3.1061) — hai nút chạy phím tắt (`VPNShortcutRunner`), hai ô tên,
///    trang `VPNShortcutGuideView`, dòng "App chạy phím tắt lần cuối". Cùng hai nút có ở sheet hub (dòng "VPN 1.1.1.1").
/// 3. Trình duyệt & phim — dẫn sang `SystemDNSGuideView` (đổi DNS / IP cho cả máy), vì WebView và AVPlayer nằm ngoài
///    tầm của DNS trong app.
///
/// Không tự bọc `NavigationStack`: Cài đặt đẩy màn này vào stack của nó.
struct NetworkSettingsView: View {
    @AppStorage(EncryptedDNSPolicy.enabledKey) private var dnsEnabled = EncryptedDNSPolicy.defaultEnabled
    @AppStorage(EncryptedDNSPolicy.resolverKey) private var resolver = EncryptedDNSPolicy.defaultResolver
    @AppStorage(VPNShortcutLauncher.Action.on.nameKey) private var vpnOnName = VPNShortcutLauncher.Action.on.defaultName
    @AppStorage(VPNShortcutLauncher.Action.off.nameKey) private var vpnOffName = VPNShortcutLauncher.Action.off.defaultName
    @AppStorage(VPNShortcutLauncher.lastRunAtKey) private var vpnLastRunAt: Double = 0
    @AppStorage(VPNShortcutLauncher.lastRunInfoKey) private var vpnLastRunInfo = ""

    private var repository: EncryptedDNSRepository { EncryptedDNSRepository.shared }

    var body: some View {
        Form { Group {
            dnsSection
            vpnSection
            systemSection
        }.glassSheetRows() }
        .backPageTitle("Mạng & DNS")
        .onAppear {
            repository.refreshSourceCount()
        }
        .onChange(of: dnsEnabled) { _, _ in
            repository.applySettings()
        }
        .onChange(of: resolver) { _, _ in
            repository.applySettings()
        }
    }

    // MARK: - DNS mã hoá

    private var dnsSection: some View {
        Section {
            Toggle("Bật cho cả app", isOn: $dnsEnabled)
            Picker("Máy chủ", selection: $resolver) {
                ForEach(EncryptedDNSResolver.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            HStack {
                Text("Bật riêng")
                Spacer(minLength: 8)
                Text(sourceCountText)
                    .foregroundColor(.secondary)
            }
            if repository.isNeeded {
                statusRow
                Button("Kiểm tra lại") {
                    repository.recheck()
                }
                .disabled(repository.state.isChecking)
            }
        } header: {
            SectionHelpHeader("DNS mã hoá", paragraphs: [
                "Tra tên miền qua máy chủ DNS mã hoá thay cho DNS của nhà mạng, để vào được trang bị nhà mạng chặn theo tên miền. Mặc định tắt.",
                "Bật cho cả app: áp cho mọi phần tải của app — tiện ích, nguồn Legado, ảnh bìa, ảnh truyện tranh, tải phim. Bật riêng: chỉ request trong script của tiện ích / nguồn đã bật công tắc \"DNS mã hoá (DoH)\" ở Cấu hình tiện ích hoặc Chi tiết nguồn Legado.",
                "Trình duyệt và trình phát phim/nhạc không đổi được trong app — xem mục \"Trình duyệt & phim\" bên dưới.",
                "Máy chủ không tới được thì app tự lùi về DNS thường cho tới lần kiểm tra sau (đổi mạng, mở lại app hoặc bấm Kiểm tra lại). Bật rồi mà trang vẫn bị chặn thì nhà mạng chặn kiểu khác (theo SNI hoặc theo IP) — chỉ proxy / VPN mới qua được.",
                "Máy trong mạng nhà gọi bằng tên (vd máy chủ AI tự dựng) có thể không tra được khi bật cho cả app — dùng địa chỉ IP của máy đó."
            ])
        }
    }

    private var sourceCountText: String {
        let count = repository.enabledSourceCount
        return count == 0 ? "Chưa có" : "\(count) tiện ích / nguồn"
    }

    private var statusRow: some View {
        let state = repository.state
        return HStack(spacing: 10) {
            statusIcon(state)
                .frame(width: 22)
            Text(state.statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func statusIcon(_ state: EncryptedDNSState) -> some View {
        switch state {
        case .off:
            Image(systemName: "network")
                .foregroundColor(.secondary)
        case .checking:
            ProgressView()
        case .reachable:
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
        case .fallback:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        case .waitingForNetwork:
            Image(systemName: "wifi.slash")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - VPN 1.1.1.1

    private var vpnSection: some View {
        Section {
            Button {
                VPNShortcutRunner.run(.on, from: .settings)
            } label: {
                Label("Bật VPN 1.1.1.1", systemImage: "network.badge.shield.half.filled")
            }
            Button {
                VPNShortcutRunner.run(.off, from: .settings)
            } label: {
                Label("Tắt VPN 1.1.1.1", systemImage: "shield.slash")
            }
            shortcutNameRow("Phím tắt bật", text: $vpnOnName, placeholder: VPNShortcutLauncher.Action.on.defaultName)
            shortcutNameRow("Phím tắt tắt", text: $vpnOffName, placeholder: VPNShortcutLauncher.Action.off.defaultName)
            NavigationLink(destination: VPNShortcutGuideView()) {
                Text("Cách tạo phím tắt")
            }
            HStack {
                Text("App chạy phím tắt lần cuối")
                Spacer(minLength: 8)
                Text(lastRunText)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        } header: {
            SectionHelpHeader("VPN 1.1.1.1", paragraphs: [
                "App không tự bật / tắt VPN được. Hai nút chạy hai phím tắt tạo sẵn trong app Phím tắt: phím tắt bật dùng tác vụ \"Đặt VPN\" › Kết nối, phím tắt tắt dùng \"Đặt VPN\" › Ngắt kết nối, cùng cấu hình 1.1.1.1 — xem \"Cách tạo phím tắt\".",
                "Mỗi lần bấm, app Phím tắt hiện lên giây lát rồi tự quay về đây; app không bị mở lại.",
                "Tên phím tắt phải trùng tên trong app Phím tắt, nên đặt không dấu. Hai nút cũng có ở dòng \"VPN 1.1.1.1\" của nút hub nổi.",
                "App chạy phím tắt lần cuối: giờ, Bật / Tắt và chỗ bấm của lần gần nhất app mở app Phím tắt. VPN tự bật mà giờ ở đây cũ hơn thì không phải app này bật."
            ])
        }
    }

    private func shortcutNameRow(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .foregroundColor(.secondary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
        }
    }

    /// "10:42 · Bật · hub" (hôm nay) / "24/11 10:42 · …" (ngày khác) / "Chưa có".
    private var lastRunText: String {
        guard vpnLastRunAt > 0 else { return "Chưa có" }
        let date = Date(timeIntervalSince1970: vpnLastRunAt)
        let formatter = Calendar.current.isDateInToday(date) ? Self.timeFormatter : Self.dayTimeFormatter
        let time = formatter.string(from: date)
        return vpnLastRunInfo.isEmpty ? time : "\(time) · \(vpnLastRunInfo)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter
    }()

    // MARK: - Trình duyệt & phim

    private var systemSection: some View {
        Section {
            NavigationLink(destination: SystemDNSGuideView()) {
                Label("Đổi DNS / IP cho cả iPhone", systemImage: "iphone")
            }
        } header: {
            SectionHelpHeader("Trình duyệt & phim", paragraphs: [
                "Trình duyệt, webview của tiện ích và trình phát phim/nhạc tải mạng ngoài tầm của app, nên chỉ đổi được DNS bằng cài đặt cho cả máy. Trang hướng dẫn cũng có cách đổi IP khi bị trang nguồn chặn."
            ])
        }
    }
}
