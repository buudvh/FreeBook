import SwiftUI

/// Cài đặt → Chung → **Giao diện** (1.3.636): gom các màn cài đặt về hiển thị (kiểu danh sách, nội dung nhạy cảm, bàn
/// phím) và chỉnh độ trong suốt / độ đục của nút nổi (tai nghe Reader, nút "+") cùng ngăn kéo menu ba chấm.
///
/// Thanh kéo ghi thẳng `UserDefaults` qua `@AppStorage` cùng khoá với `FloatingGlassBackground` /
/// `SideDrawerGlassBackground`, nên ô xem trước (dựng bằng đúng hai view đó) và mọi nút thật đổi theo ngay khi kéo.
struct AppearanceSettingsView: View {
    @AppStorage(GlassChromeSettings.floatingTransparencyKey)
    private var floatingTransparency = GlassChromeSettings.defaultFloatingTransparency
    @AppStorage(GlassChromeSettings.floatingFrostKey)
    private var floatingFrost = GlassChromeSettings.defaultFloatingFrost
    @AppStorage(GlassChromeSettings.drawerTransparencyKey)
    private var drawerTransparency = GlassChromeSettings.defaultDrawerTransparency
    @AppStorage(GlassChromeSettings.drawerFrostKey)
    private var drawerFrost = GlassChromeSettings.defaultDrawerFrost

    /// Nền + chữ mẫu cho ô xem trước — cùng màu nền chủ đề Tối của Reader.
    private static let previewBackground = Color(red: 0.08, green: 0.08, blue: 0.09)
    private static let previewText = "Gió đêm thổi qua dãy núi phía tây, mang theo mùi cỏ dại và tiếng chuông xa. "
        + "Cô dừng lại bên bờ suối, nhìn ánh trăng vỡ ra trên mặt nước rồi chậm rãi bước tiếp về phía làng."

    var body: some View {
        Form {
            Section {
                NavigationLink(destination: BookListLayoutSettingsView()) {
                    Label("Kiểu hiển thị danh sách", systemImage: "square.grid.2x2")
                }
                NavigationLink(destination: NsfwSettingsView()) {
                    Label("Nội dung nhạy cảm (NSFW)", systemImage: "eye.slash")
                }
                NavigationLink(destination: KeyboardSettingsView()) {
                    Label("Bàn phím & ô nhập", systemImage: "keyboard")
                }
            }

            Section {
                percentSlider("Độ trong suốt", value: $floatingTransparency)
                percentSlider("Độ đục", value: $floatingFrost)
                floatingPreview
                Button("Đặt lại mặc định") {
                    floatingTransparency = GlassChromeSettings.defaultFloatingTransparency
                    floatingFrost = GlassChromeSettings.defaultFloatingFrost
                }
                .frame(maxWidth: .infinity)
            } header: {
                Text("Nút nổi (tai nghe, nút +)")
            } footer: {
                Text("Áp cho nút tai nghe trong Reader và nút + ở các màn danh sách. Độ trong suốt là lớp màu nền của nút; độ đục là độ nhoè của kính.")
            }

            Section {
                percentSlider("Độ trong suốt", value: $drawerTransparency)
                percentSlider("Độ đục", value: $drawerFrost)
                drawerPreview
                Button("Đặt lại mặc định") {
                    drawerTransparency = GlassChromeSettings.defaultDrawerTransparency
                    drawerFrost = GlassChromeSettings.defaultDrawerFrost
                }
                .frame(maxWidth: .infinity)
            } header: {
                Text("Menu ba chấm")
            } footer: {
                Text("Ngăn kéo trượt ra từ mép phải khi bấm nút … ở các màn.")
            }
        }
        .navigationTitle("Giao diện")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Thanh kéo

    private func percentSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1, step: 0.05)
                .accessibilityLabel(title)
        }
    }

    // MARK: - Xem trước

    private var previewTextBlock: some View {
        Text(Self.previewText)
            .font(.footnote)
            .foregroundColor(Color.white.opacity(0.75))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
    }

    private var floatingPreview: some View {
        ZStack(alignment: .bottomTrailing) {
            previewTextBlock
            HStack(spacing: 10) {
                previewCircle(systemImage: "plus")
                previewCircle(systemImage: "headphones")
            }
            .padding(10)
        }
        .frame(height: 112)
        .background(Self.previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Xem trước nút nổi")
    }

    private func previewCircle(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 52, height: 52)
            .background { FloatingGlassBackground() }
    }

    private var drawerPreview: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                previewTextBlock
                VStack(alignment: .leading, spacing: 10) {
                    Label("Thêm quy tắc", systemImage: "plus")
                    Label("Nhập cấu hình", systemImage: "square.and.arrow.down")
                    Label("Xuất cấu hình", systemImage: "square.and.arrow.up")
                }
                .font(.footnote)
                .foregroundColor(.white)
                .padding(12)
                .frame(width: proxy.size.width * 0.58, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background { SideDrawerGlassBackground() }
            }
        }
        .frame(height: 112)
        .background(Self.previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Xem trước menu ba chấm")
    }
}
