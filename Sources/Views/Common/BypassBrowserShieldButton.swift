import SwiftUI

/// Nút **khiên** trong ô URL của trình duyệt người dùng (thay ổ khoá cũ) + bảng nổi chỉnh theo tên miền (plan §3.1).
///
/// Biểu tượng theo `store.decision(for: tab)` của trang đang xem:
/// - `checkmark.shield.fill` xanh: đang chặn quảng cáo trên trang này;
/// - `shield.slash`: đã tắt cho trang này (hoặc tắt chung);
/// - `globe`: trang Home / `about:blank` — không áp dụng, không bấm được.
///
/// `decision(for:)` đọc `BrowserSitePreferenceStore` + `UserDefaults`, cả hai đều không quan sát được ⇒ view đọc
/// kèm `BrowserSitePreferenceList.shared.items` và `@AppStorage` của cài đặt chung chỉ để SwiftUI vẽ lại khi người
/// dùng đổi ở bảng nổi này hoặc ở màn Cài đặt Trình duyệt.
struct BypassBrowserShieldButton: View {
    @ObservedObject var store: BypassBrowserTabStore
    @ObservedObject var tab: BypassBrowserTab
    /// Mở màn Cài đặt Trình duyệt (sheet do `BypassWebView` giữ). Chỉ gọi **sau** khi bảng nổi đã đóng: trình bày
    /// sheet trong lúc popover còn đang đóng thì UIKit bỏ qua lặng lẽ.
    let onOpenSettings: () -> Void

    @AppStorage(WebContentSettings.adBlockEnabledKey) private var globalAdBlock = true
    @AppStorage(WebContentSettings.browserDefaultDesktopKey) private var globalDesktop = false
    @State private var showingPanel = false
    @State private var opensSettingsAfterDismiss = false

    var body: some View {
        // Chỉ để đăng ký phụ thuộc (xem doc của type) — giá trị thật lấy qua `store.decision(for:)`.
        let _ = BrowserSitePreferenceList.shared.items
        let _ = (globalAdBlock, globalDesktop)
        let decision = store.decision(for: tab)

        Button {
            showingPanel = true
        } label: {
            shieldIcon(for: decision)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(decision == nil)
        // Hitbox 32×36 nhưng không làm ô URL cao thêm: ô đã có đệm dọc 8pt, đệm trái 10pt.
        .padding(.vertical, -8)
        .padding(.leading, -6)
        .accessibilityLabel(accessibilityText(for: decision))
        .popover(isPresented: $showingPanel, arrowEdge: .bottom) {
            Panel(store: store, tab: tab) {
                opensSettingsAfterDismiss = true
                showingPanel = false
            }
            .presentationCompactAdaptation(.popover)
            .preferredColorScheme(.dark)
        }
        .onChange(of: showingPanel) { _, isShowing in
            guard !isShowing, opensSettingsAfterDismiss else { return }
            opensSettingsAfterDismiss = false
            // Chờ hoạt ảnh đóng popover xong rồi mới mở sheet (như độ trễ 0,3 s ở `ExtensionConfigView+Browser`).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onOpenSettings()
            }
        }
    }

    @ViewBuilder
    private func shieldIcon(for decision: WebContentDecision?) -> some View {
        if let decision {
            Image(systemName: decision.adBlock ? "checkmark.shield.fill" : "shield.slash")
                .foregroundColor(decision.adBlock ? .green : .secondary)
        } else {
            Image(systemName: "globe")
                .foregroundColor(.secondary)
        }
    }

    private func accessibilityText(for decision: WebContentDecision?) -> String {
        guard let decision else { return "Trang chủ trình duyệt" }
        return decision.adBlock ? "Đang chặn quảng cáo trên trang này" : "Đang tắt chặn quảng cáo trên trang này"
    }

    /// Host trang tab đang hiển thị — cùng điều kiện với `BypassBrowserTabStore.decision(for:)` (chỉ http/https có
    /// host). Đây là host **ghi** chỉnh riêng: không dùng `preference.domain` (có thể là tên miền cha).
    static func pageHost(of tab: BypassBrowserTab) -> String? {
        guard let url = URL(string: tab.urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return host
    }
}

// MARK: - Bảng nổi

extension BypassBrowserShieldButton {
    /// Nội dung popover: tên miền + trạng thái, hai công tắc nhớ theo tên miền, lối vào Cài đặt Trình duyệt.
    /// Là view riêng để tự theo dõi phụ thuộc (popover vẽ trong cây trình bày khác với nút).
    fileprivate struct Panel: View {
        @ObservedObject var store: BypassBrowserTabStore
        @ObservedObject var tab: BypassBrowserTab
        let onOpenSettings: () -> Void

        @AppStorage(WebContentSettings.adBlockEnabledKey) private var globalAdBlock = true
        @AppStorage(WebContentSettings.browserDefaultDesktopKey) private var globalDesktop = false

        private enum SiteField {
            case adBlock
            case desktop
        }

        var body: some View {
            let _ = BrowserSitePreferenceList.shared.items
            let _ = (globalAdBlock, globalDesktop)
            if let decision = store.decision(for: tab), let host = BypassBrowserShieldButton.pageHost(of: tab) {
                content(decision: decision, host: host)
            } else {
                // Tab vừa về Home trong lúc bảng đang mở: không còn gì để chỉnh.
                Text("Trang này không áp dụng chặn quảng cáo")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(14)
            }
        }

        private func content(decision: WebContentDecision, host: String) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                header(decision: decision, host: host)

                Divider()
                    .background(Color.white.opacity(0.12))

                toggleRow(
                    icon: "shield.lefthalf.filled",
                    title: "Chặn quảng cáo",
                    isOn: binding(decision.adBlock, field: .adBlock, host: host)
                )
                toggleRow(
                    icon: "desktopcomputer",
                    title: "Xem bản máy tính",
                    isOn: binding(decision.desktop, field: .desktop, host: host)
                )

                Divider()
                    .background(Color.white.opacity(0.12))

                Button(action: onOpenSettings) {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24)
                        Text("Cài đặt trình duyệt")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.white)
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(minWidth: 270, maxWidth: 300)
        }

        private func header(decision: WebContentDecision, host: String) -> some View {
            HStack(spacing: 10) {
                Image(systemName: decision.adBlock ? "checkmark.shield.fill" : "shield.slash")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(decision.adBlock ? .green : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BrowserSitePreferenceStore.normalizedDomain(for: host) ?? host)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(statusText(adBlock: decision.adBlock))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }

        /// N = số bộ lọc đang bật đã biên dịch xong. N = 0 (đang biên dịch lần đầu, hoặc người dùng tắt hết bộ lọc)
        /// mà vẫn ghi "bằng 0 bộ lọc" thì sai sự thật ⇒ câu riêng.
        private func statusText(adBlock: Bool) -> String {
            guard adBlock else { return "Đang tắt chặn quảng cáo" }
            let count = AdBlockRuleListProvider.shared.readyFilterCount
            return count > 0 ? "Đã chặn quảng cáo bằng \(count) bộ lọc" : "Chưa có bộ lọc nào sẵn sàng"
        }

        private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
            Toggle(isOn: isOn) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Nhớ cho trang này")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tint(.green)
        }

        /// Như `ExtensionConfigView.savesHistoryBinding`: chụp giá trị trong lượt vẽ, ghi qua `MainActor.assumeIsolated`.
        private func binding(_ isOn: Bool, field: SiteField, host: String) -> Binding<Bool> {
            Binding(
                get: { isOn },
                set: { value in
                    guard value != isOn else { return }
                    MainActor.assumeIsolated { remember(value, field: field, host: host) }
                }
            )
        }

        /// Ghi theo **host của tab** (không theo `preference.domain`): tra cứu gộp giá trị từ tên miền cha, nên ghi
        /// lên domain cha sẽ đổi luôn mọi tên miền con của nó.
        ///
        /// Không tạo mục thừa: ghi `nil` trước, rồi tính lại giá trị **kế thừa** (tên miền cha, sau đó cài đặt
        /// chung). Kế thừa đã ra đúng giá trị người dùng chọn ⇒ để `nil`, trang tiếp tục theo mặc định; khác mới ghi
        /// giá trị tường minh. Không so thẳng với cài đặt chung: nếu `b.com` đã tắt chặn QC mà người dùng bật lại ở
        /// `m.b.com` (bằng mặc định chung), ghi `nil` sẽ khiến `m.b.com` vẫn thừa hưởng "tắt" từ `b.com`.
        @MainActor
        private func remember(_ value: Bool, field: SiteField, host: String) {
            let list = BrowserSitePreferenceList.shared
            write(nil, field: field, host: host, list: list)
            let inherited = WebContentPolicy.decision(for: .userBrowser(host: host))
            let inheritedValue = field == .adBlock ? inherited.adBlock : inherited.desktop
            if inheritedValue != value {
                write(value, field: field, host: host, list: list)
            }
            let what = field == .adBlock ? "chặn quảng cáo" : "bản máy tính"
            AppLogger.shared.log("🛡️ [BypassBrowser] \(host): \(value ? "bật" : "tắt") \(what) (nhớ theo tên miền)")
            store.reloadActiveTabApplyingSitePreferences()
        }

        @MainActor
        private func write(_ value: Bool?, field: SiteField, host: String, list: BrowserSitePreferenceList) {
            switch field {
            case .adBlock: list.setAdBlock(value, forHost: host)
            case .desktop: list.setDesktop(value, forHost: host)
            }
        }
    }
}
