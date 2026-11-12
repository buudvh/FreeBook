import SwiftUI

/// Mục **"Viên thuốc nổi"** của Cài đặt › Chung › Giao diện (anh Bửu duyệt mockup 2026-11-11): chọn một viên (Đĩa nghe /
/// Hub / Trình duyệt) ở thanh phân đoạn rồi chỉnh **độ trong suốt**, **độ đục** và **độ nhô** của riêng viên đó
/// (`EdgePillSettings`). Viên thuốc thật đổi ngay khi kéo (container nghe `UserDefaults`), ô xem trước vẽ cả ba viên.
///
/// - Độ nhô thấp nhất = nửa chiều cao ⇒ hình bán nguyệt (bìa / icon lọt nửa ra ngoài mép).
/// - Công tắc "Xem thử nháy đỏ" chỉ cho ô xem trước: hub và nút trình duyệt nháy theo độ trong suốt + độ đục của chúng.
/// - Ô xem trước chỉ cắt khung chữ nhật (`clipped`), không cắt bằng mặt nạ bo góc (kính iOS hỏng khi lớp cha bị mặt nạ).
struct EdgePillSettingsSection: View {
    @State private var selectedKind: EdgePillSettings.Kind = .disc
    @State private var previewsPulse = false

    var body: some View {
        Section {
            Picker("Viên thuốc", selection: $selectedKind) {
                ForEach(EdgePillSettings.Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Rows(kind: selectedKind)
                .id(selectedKind)

            Toggle("Xem thử nháy đỏ", isOn: $previewsPulse)
            preview
        } header: {
            SectionHelpHeader("Viên thuốc nổi", paragraphs: [
                "Đĩa nghe, hub và nút trình duyệt thu nhỏ — các nửa viên thuốc dính mép màn hình. Chọn một viên ở thanh trên rồi chỉnh riêng cho viên đó.",
                "Độ trong suốt là lớp màu nền của viên, bìa / icon và màu nháy đỏ cùng mờ theo. Độ đục là độ nhoè của kính.",
                "Độ nhô là phần viên thuốc nhô ra khỏi mép. Nhỏ nhất là hình bán nguyệt: bìa / icon chỉ còn ló một nửa."
            ])
        }
    }

    /// Nền bìa giả + ba viên: hub và đĩa ở mép phải, nút trình duyệt ở mép trái.
    private var preview: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(Self.previewCoverColors.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Self.previewCoverColors[index])
                }
            }
            .padding(10)
            .background(Color(red: 0.08, green: 0.08, blue: 0.09))

            VStack(alignment: .trailing, spacing: 12) {
                PreviewPill(kind: .hub, edge: .right, isPulsing: previewsPulse)
                PreviewPill(kind: .disc, edge: .right, isPulsing: false)
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            PreviewPill(kind: .browser, edge: .left, isPulsing: previewsPulse)
                .padding(.top, 38)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 128)
        .clipped()
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Xem trước viên thuốc nổi")
    }

    private static let previewCoverColors: [Color] = [
        Color(red: 0.06, green: 0.43, blue: 0.34),
        Color(red: 0.24, green: 0.20, blue: 0.54),
        Color(red: 0.60, green: 0.24, blue: 0.11),
        Color(red: 0.09, green: 0.37, blue: 0.65)
    ]

    // MARK: - Lồng (một type chính mỗi file)

    /// Ba thanh kéo + nút đặt lại của **một** viên — khoá `@AppStorage` theo viên nên dựng lại khi đổi viên (`.id`).
    private struct Rows: View {
        let kind: EdgePillSettings.Kind

        @AppStorage private var transparency: Double
        @AppStorage private var frost: Double
        @AppStorage private var width: Double

        init(kind: EdgePillSettings.Kind) {
            self.kind = kind
            _transparency = AppStorage(wrappedValue: EdgePillSettings.defaultTransparency, kind.transparencyKey)
            _frost = AppStorage(wrappedValue: EdgePillSettings.defaultFrost, kind.frostKey)
            _width = AppStorage(wrappedValue: kind.defaultWidth, kind.widthKey)
        }

        var body: some View {
            sliderRow("Độ trong suốt", value: $transparency, range: 0...1, step: 0.05, valueText: transparencyText)
            sliderRow("Độ đục", value: $frost, range: 0...1, step: GlassFrostLevel.step, valueText: frostText)
            sliderRow(
                "Độ nhô ra khỏi mép",
                value: $width,
                range: kind.widthRange,
                step: EdgePillSettings.widthStep,
                valueText: widthText
            )
            Button("Đặt lại \(kind.title)") {
                transparency = EdgePillSettings.defaultTransparency
                frost = EdgePillSettings.defaultFrost
                width = kind.defaultWidth
            }
            .frame(maxWidth: .infinity)
        }

        private var transparencyText: String {
            let percent = Int((transparency * 100).rounded())
            return transparency == EdgePillSettings.defaultTransparency ? "\(percent)% · Mặc định" : "\(percent)%"
        }

        private var frostText: String {
            let snapped = (frost / GlassFrostLevel.step).rounded() * GlassFrostLevel.step
            return "\(Int((snapped * 100).rounded()))% · \(GlassFrostLevel(frost: frost).title)"
        }

        private var widthText: String {
            let shown = EdgePillSettings.clampedWidth(width, for: kind)
            let points = "\(Int(shown.rounded())) pt"
            if shown <= kind.widthRange.lowerBound { return points + " · Bán nguyệt" }
            if shown == kind.defaultWidth { return points + " · Mặc định" }
            return points
        }

        private func sliderRow(
            _ title: String,
            value: Binding<Double>,
            range: ClosedRange<Double>,
            step: Double,
            valueText: String
        ) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(valueText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: value, in: range, step: step)
                    .accessibilityLabel("\(title) của \(kind.title)")
            }
        }
    }

    /// Một viên trong ô xem trước: cùng kính / độ nhô / độ mờ với viên thật (đọc cùng khoá `EdgePillSettings`).
    private struct PreviewPill: View {
        let kind: EdgePillSettings.Kind
        let edge: EdgeDirection
        let isPulsing: Bool

        @AppStorage private var transparency: Double
        @AppStorage private var width: Double
        @State private var isPulseBright = false

        init(kind: EdgePillSettings.Kind, edge: EdgeDirection, isPulsing: Bool) {
            self.kind = kind
            self.edge = edge
            self.isPulsing = isPulsing
            _transparency = AppStorage(wrappedValue: EdgePillSettings.defaultTransparency, kind.transparencyKey)
            _width = AppStorage(wrappedValue: kind.defaultWidth, kind.widthKey)
        }

        var body: some View {
            let shape = EdgePillShape(edge: edge)
            let contentSize: CGFloat = kind == .disc ? 32 : 24
            let inset = EdgePillShape.contentInset(height: kind.height, content: contentSize)
            FloatingGlassBackground(shape: AnyShape(shape), pill: kind)
                .overlay {
                    if isPulsing {
                        shape.fill(pulseColor)
                    }
                }
                .overlay(alignment: EdgePillShape.contentAlignment(for: edge)) {
                    content(size: contentSize)
                        .opacity(contentOpacity)
                        .padding(EdgePillShape.contentPadding(for: edge), inset)
                }
                .frame(width: CGFloat(EdgePillSettings.clampedWidth(width, for: kind)), height: kind.height)
                .animation(
                    isPulsing
                        ? .easeInOut(duration: FloatingHubPulseView.pulseHalfPeriod).repeatForever(autoreverses: true)
                        : .easeInOut(duration: 0.2),
                    value: isPulseBright
                )
                .onAppear { isPulseBright = isPulsing }
                .onChange(of: isPulsing) { _, newValue in
                    isPulseBright = newValue
                }
        }

        private var contentOpacity: Double {
            1 - min(1, max(0, transparency))
        }

        /// Đỏ nội suy như viên thật, alpha = `1 − trong suốt` của viên.
        private var pulseColor: Color {
            let level = isPulseBright ? 1.0 : FloatingHubPulseView.pulseDimLevel
            let rgb = FloatingHubPulseView.pulseRGB(level: level)
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: contentOpacity)
        }

        @ViewBuilder
        private func content(size: CGFloat) -> some View {
            switch kind {
            case .disc:
                Circle()
                    .fill(Color(red: 0.06, green: 0.43, blue: 0.34))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: size, height: size)
            case .hub, .browser:
                Image(systemName: kind == .hub ? "square.stack.3d.up" : "safari")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: size, height: size)
            }
        }
    }
}
