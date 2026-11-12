import SwiftUI

/// Màn **Trình duyệt** (Cài đặt → Đọc & Nghe; cũng mở dạng sheet từ bảng nổi của nút khiên trong trình duyệt) — thay
/// màn "Trình duyệt hiển thị" cũ. Đúng thứ tự plan §3.2:
/// 1. Chặn quảng cáo — công tắc chung + chặn cửa sổ bật lên;
/// 2. Bộ lọc — `BrowserFilterListSection`;
/// 3. Chế độ hiển thị — mặc định Điện thoại/Máy tính của trình duyệt;
/// 4. Dịch trang — công tắc chung phồn → giản (`BrowserTranslatePolicy.convertsTraditionalKey`, 1.3.684; bước riêng,
///    chạy cả khi không dịch trang từ 1.3.846);
/// 5. Trang đã chỉnh riêng — `BrowserSitePreferencesSection`;
/// 6. Trình duyệt của tiện ích — công tắc thu nhỏ cũ (`VisibleBrowserSettings.openMinimizedKey`).
///
/// Công tắc chung ghi thẳng `UserDefaults` qua `@AppStorage` với khoá của `WebContentSettings` (mặc định khớp
/// `WebContentSettings.registerDefaults()`); có hiệu lực từ lượt nạp trang kế tiếp, không nạp lại tab đang mở. Riêng
/// phồn → giản: mở từ trình duyệt thì `BypassWebView` áp lại ngay cho các tab; mở từ Cài đặt thì áp từ lượt nạp trang kế
/// tiếp.
///
/// Không tự bọc `NavigationStack`: Cài đặt đẩy màn này vào stack của nó; sheet của trình duyệt tự bọc.
struct BrowserSettingsView: View {
    /// `true` khi mở dạng sheet (trình duyệt): hiện tiêu đề trang. Không còn nút "Xong" — vuốt xuống để đóng; giữ
    /// tên cũ để `BypassWebView` khỏi đổi chỗ gọi.
    var showsDoneButton = false

    @AppStorage(WebContentSettings.adBlockEnabledKey) private var adBlockEnabled = true
    @AppStorage(WebContentSettings.popupBlockingEnabledKey) private var popupBlockingEnabled = true
    @AppStorage(WebContentSettings.browserDefaultDesktopKey) private var browserDefaultDesktop = false
    @AppStorage(VisibleBrowserSettings.openMinimizedKey) private var openMinimized = false
    @AppStorage(BrowserTranslatePolicy.convertsTraditionalKey) private var convertsTraditional = false

    var body: some View {
        Form { Group {
            adBlockSection
            BrowserFilterListSection()
            displayModeSection
            pageTranslateSection
            BrowserSitePreferencesSection()
            extensionBrowserSection
        }.glassSheetRows() }
        .pageTitle("Trình duyệt", style: showsDoneButton ? .leading : .centered)
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
            SectionHelpHeader("Chặn quảng cáo", paragraphs: ["Chặn quảng cáo áp cho trình duyệt và webview của tiện ích; từng tiện ích chỉnh riêng được trong Cấu hình tiện ích. Chặn cửa sổ bật lên: trang tự mở tab sang tên miền khác sẽ bị chặn, link bạn bấm vẫn mở bình thường."])
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
            SectionHelpHeader("Chế độ hiển thị", paragraphs: ["Chỉ áp cho trình duyệt. Tiện ích luôn dùng điện thoại trừ khi bật riêng."])
        }
    }

    // MARK: - Dịch trang

    private var pageTranslateSection: some View {
        Section {
            Toggle("Chuyển phồn thể → giản thể", isOn: $convertsTraditional)
        } header: {
            SectionHelpHeader("Dịch trang", paragraphs: [
                "Phồn → giản là bước riêng, chạy cả khi không dịch trang: bật mà không dịch thì trang hiện chữ giản thể. Khi dịch QT, chữ được chuyển trước rồi mới tra từ điển nên dịch sát hơn.",
                "Áp cho chữ trên trang, tiêu đề tab và câu gốc của menu bôi đen (Dịch QT, Tra từ điển, Sao chép bản dịch). Trang giản thể cũng bị chuyển, có thể bị đổi vài chữ mập mờ.",
                "Chỉnh riêng từng trang ở công tắc \"Phồn → giản\" trong menu khiên của trình duyệt."
            ])
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
