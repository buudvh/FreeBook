import SwiftUI

/// Màn **Mạng & DNS** (Cài đặt › Chung, 1.3.825; mặc định tắt + bật riêng từng nguồn từ 1.3.828, 1.3.831).
/// 1. DNS mã hoá — công tắc **"Bật cho cả app"** (`EncryptedDNSPolicy`, mặc định tắt), máy chủ dùng chung cho cả bật
///    chung lẫn bật riêng, dòng **"Bật riêng: N tiện ích / nguồn"** (cờ `Extension.encryptedDNSEnabled` đặt ở Cấu hình
///    tiện ích / Chi tiết nguồn Legado), trạng thái + "Kiểm tra lại" khi có ai cần (`EncryptedDNSRepository`).
/// 2. Trình duyệt & phim — dẫn sang `SystemDNSGuideView` (đổi DNS / IP cho cả máy), vì WebView và AVPlayer nằm ngoài
///    tầm của DNS trong app.
///
/// Không tự bọc `NavigationStack`: Cài đặt đẩy màn này vào stack của nó.
struct NetworkSettingsView: View {
    @AppStorage(EncryptedDNSPolicy.enabledKey) private var dnsEnabled = EncryptedDNSPolicy.defaultEnabled
    @AppStorage(EncryptedDNSPolicy.resolverKey) private var resolver = EncryptedDNSPolicy.defaultResolver

    private var repository: EncryptedDNSRepository { EncryptedDNSRepository.shared }

    var body: some View {
        Form { Group {
            dnsSection
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
