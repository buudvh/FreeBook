import SwiftUI

/// Màn **Trình duyệt** (Cài đặt → Đọc & Nghe; cũng mở dạng sheet từ bảng nổi của nút khiên trong trình duyệt) — thay
/// màn "Trình duyệt hiển thị" cũ. Đúng thứ tự plan §3.2:
/// 1. Chặn quảng cáo — công tắc chung + chặn cửa sổ bật lên;
/// 2. Bộ lọc — `BrowserFilterListSection`;
/// 3. Chế độ hiển thị — mặc định Điện thoại/Máy tính của trình duyệt;
/// 4. Trang đã chỉnh riêng — `BrowserSitePreferencesSection`;
/// 5. Trình duyệt của tiện ích — công tắc thu nhỏ cũ (`VisibleBrowserSettings.openMinimizedKey`).
///
/// Công tắc chung ghi thẳng `UserDefaults` qua `@AppStorage` với khoá của `WebContentSettings` (mặc định khớp
/// `WebContentSettings.registerDefaults()`); có hiệu lực từ lượt nạp trang kế tiếp, không nạp lại tab đang mở.
///
/// Không tự bọc `NavigationStack`: Cài đặt đẩy màn này vào stack của nó; sheet của trình duyệt tự bọc.
struct BrowserSettingsView: View {
    /// `true` khi mở dạng sheet (trình duyệt): thêm nút "Xong" để đóng.
    var showsDoneButton = false

    @Environment(\.dismiss) private var dismiss

    @AppStorage(WebContentSettings.adBlockEnabledKey) private var adBlockEnabled = true
    @AppStorage(WebContentSettings.popupBlockingEnabledKey) private var popupBlockingEnabled = true
    @AppStorage(WebContentSettings.browserDefaultDesktopKey) private var browserDefaultDesktop = false
    @AppStorage(VisibleBrowserSettings.openMinimizedKey) private var openMinimized = false

    var body: some View {
        Form {
            adBlockSection
            BrowserFilterListSection()
            displayModeSection
            BrowserSitePreferencesSection()
            extensionBrowserSection
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
        .navigationTitle("Trình duyệt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            // Menu khiên có thể vừa ghi theo tên miền từ trình duyệt — đọc lại cho chắc.
            BrowserSitePreferenceList.shared.reload()
        }
    }

    // MARK: - Chặn quảng cáo

    private var adBlockSection: some View {
        Section {
            Toggle("Chặn quảng cáo", isOn: $adBlockEnabled)
            Toggle(isOn: $popupBlockingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chặn cửa sổ bật lên")
                    Text("Chỉ trình duyệt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Chặn quảng cáo")
        } footer: {
            Text("Chặn quảng cáo áp cho trình duyệt và webview của tiện ích; từng tiện ích chỉnh riêng được trong Cấu hình tiện ích. Chặn cửa sổ bật lên: trang tự mở tab sang tên miền khác sẽ bị chặn, link bạn bấm vẫn mở bình thường.")
        }
    }

    // MARK: - Chế độ hiển thị

    private var displayModeSection: some View {
        Section {
            HStack(spacing: 12) {
                Text("Mặc định")
                Spacer(minLength: 8)
                Picker("Mặc định", selection: $browserDefaultDesktop) {
                    Text("Điện thoại").tag(false)
                    Text("Máy tính").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        } header: {
            Text("Chế độ hiển thị")
        } footer: {
            Text("Chỉ áp cho trình duyệt. Tiện ích luôn dùng điện thoại trừ khi bật riêng.")
        }
    }

    // MARK: - Trình duyệt của tiện ích

    /// Giữ nguyên công tắc, khoá và mô tả của màn "Trình duyệt hiển thị" cũ.
    private var extensionBrowserSection: some View {
        Section {
            Toggle(isOn: $openMinimized) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mở ở chế độ thu nhỏ")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Khi extension mở trình duyệt hiển thị mới, trình duyệt khởi tạo ngay ở dạng thu nhỏ (widget nổi) thay vì bật lên toàn màn hình. Trình duyệt đang mở không bị ảnh hưởng.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Trình duyệt của tiện ích")
        }
    }
}
