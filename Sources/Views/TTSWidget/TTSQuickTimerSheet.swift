import SwiftUI
import UIKit

/// Bottom Sheet hiện đại điều khiển Hẹn giờ tắt và Cài đặt nhanh cho TTS Widget.
struct TTSQuickTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ttsManager = TTSManager.shared
    @State private var customMinutes: Double = 90.0
    /// Đọc thẳng khoá `UserDefaults` để sheet Hẹn giờ tự cập nhật khi đổi chế độ E-Ink.
    @AppStorage(EInkModeSettings.Key.enabled) private var isEInkEnabled = false
    @AppStorage(EInkModeSettings.Key.paperColor) private var paperColorRaw = EInkModeSettings.EInkPaperColor.gray.rawValue

    private let presetMinutes = [15, 30, 45, 60, 90]
    private var paperCanvas: Color {
        EInkPalette.paperCanvasColor(for: EInkModeSettings.EInkPaperColor(rawValue: paperColorRaw) ?? .pureDeep)
    }
    private var paperCard: Color {
        EInkPalette.paperCardColor(for: EInkModeSettings.EInkPaperColor(rawValue: paperColorRaw) ?? .pureDeep)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. Banner trạng thái Hẹn giờ hiện tại
                    activeTimerStatusCard

                    // 2. Lưới các mốc hẹn giờ nhanh
                    presetGridSection

                    // 3. Tuỳ chỉnh số phút
                    customDurationSection

                    // 4. Phím tắt mở cài đặt giọng đọc
                    settingsShortcutSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(isEInkEnabled ? paperCanvas : Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Hẹn giờ tắt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            ttsManager.showingSettingsSheet = true
                        }
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isEInkEnabled ? EInkPalette.ink : .blue)
                    }
                    .accessibilityLabel("Cài đặt giọng đọc & Tốc độ")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(isEInkEnabled ? EInkPalette.ink : .secondary)
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if case .minutes(let mins) = ttsManager.timerMode {
                customMinutes = Double(mins)
            }
        }
    }

    // MARK: - Subviews

    /// Card hiển thị trạng thái hẹn giờ đang hoạt động
    private var activeTimerStatusCard: some View {
        Group {
            if ttsManager.timerMode != .off {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(isEInkEnabled ? paperCard : Color.orange.opacity(0.18))
                            .frame(width: 44, height: 44)
                            .overlay { if isEInkEnabled { Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
                        Image(systemName: "timer")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(isEInkEnabled ? EInkPalette.ink : Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Đang hẹn giờ tắt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)

                        if case .endOfChapter = ttsManager.timerMode {
                            Text("Dừng khi hết chương")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(isEInkEnabled ? EInkPalette.ink : Color.orange)
                        } else {
                            Text(ttsManager.sleepTimerBadgeText.isEmpty ? "\(Int(customMinutes)) phút" : ttsManager.sleepTimerBadgeText)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(isEInkEnabled ? EInkPalette.ink : Color.orange)
                        }
                    }

                    Spacer()

                    Button(action: {
                        triggerHaptic()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            ttsManager.cancelSleepTimer()
                        }
                    }) {
                        Text("Hủy")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(isEInkEnabled ? EInkPalette.ink : .red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(isEInkEnabled ? paperCard : Color.red.opacity(0.12)))
                            .overlay { if isEInkEnabled { Capsule().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isEInkEnabled ? paperCard : Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isEInkEnabled ? EInkPalette.ink : Color.orange.opacity(0.35), lineWidth: isEInkEnabled ? EInkPalette.borderWidth : 1.5)
                        )
                )
                .einkShadow(Color.orange.opacity(0.08), radius: 8, y: 3)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isEInkEnabled ? EInkPalette.ink : .secondary)
                    Text("Chưa kích hoạt hẹn giờ tắt")
                        .font(.subheadline)
                        .foregroundStyle(isEInkEnabled ? EInkPalette.ink : .secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isEInkEnabled ? paperCard : Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay { if isEInkEnabled { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
                )
            }
        }
    }

    /// Lưới các mốc hẹn giờ phổ biến
    private var presetGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chọn nhanh mốc hẹn giờ")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(presetMinutes, id: \.self) { mins in
                    let isSelected: Bool = {
                        if case .minutes(let activeMins) = ttsManager.timerMode {
                            return activeMins == mins
                        }
                        return false
                    }()

                    presetButton(
                        title: "\(mins) phút",
                        icon: "clock.fill",
                        isSelected: isSelected
                    ) {
                        triggerHaptic()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            ttsManager.startSleepTimer(minutes: mins)
                        }
                    }
                }

                // Mốc dừng khi hết chương
                let isEndOfChapterSelected: Bool = {
                    if case .endOfChapter = ttsManager.timerMode {
                        return true
                    }
                    return false
                }()

                presetButton(
                    title: "Hết chương",
                    icon: "bookmark.fill",
                    isSelected: isEndOfChapterSelected
                ) {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        ttsManager.setStopAtEndOfChapter()
                    }
                }
            }
        }
    }

    /// Nút mốc hẹn giờ
    private func presetButton(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let iconForeground: Color = isEInkEnabled ? (isSelected ? .white : EInkPalette.ink) : (isSelected ? .white : .orange)
        let titleForeground: Color = isEInkEnabled ? (isSelected ? .white : EInkPalette.ink) : (isSelected ? .white : .primary)
        let fill: Color = isEInkEnabled ? (isSelected ? .black : paperCard) : (isSelected ? .orange : Color(uiColor: .secondarySystemGroupedBackground))
        let stroke: Color = isEInkEnabled ? EInkPalette.ink : .orange
        let strokeWidth: CGFloat = isEInkEnabled && isSelected ? EInkPalette.selectedBorderWidth : 1.5
        return Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(iconForeground)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .medium)
                    .foregroundStyle(titleForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? stroke : Color.clear, lineWidth: strokeWidth)
            )
            .einkShadow(isSelected ? Color.orange.opacity(0.3) : Color.black.opacity(0.04), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// Mục tuỳ chỉnh số phút với Slider & Stepper
    private var customDurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tuỳ chỉnh thời gian")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)

            VStack(spacing: 14) {
                HStack {
                    Button(action: {
                        triggerHaptic()
                        customMinutes = max(1, customMinutes - 1)
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(isEInkEnabled ? EInkPalette.ink : Color.orange)
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text("\(Int(customMinutes))")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)
                        Text("phút")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        triggerHaptic()
                        customMinutes = min(180, customMinutes + 1)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(isEInkEnabled ? EInkPalette.ink : Color.orange)
                    }
                }
                .padding(.horizontal, 8)

                Slider(value: $customMinutes, in: 1...180, step: 1)
                    .tint(isEInkEnabled ? .primary : .orange)

                Button(action: {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        ttsManager.startSleepTimer(minutes: Int(customMinutes))
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                        Text("Hẹn giờ \(Int(customMinutes)) phút")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(isEInkEnabled ? EInkPalette.selectedContent : .white)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isEInkEnabled ? EInkPalette.selectedFill : Color.orange))
                    .einkShadow(Color.orange.opacity(0.3), radius: 6, y: 3)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEInkEnabled ? paperCard : Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay { if isEInkEnabled { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
            )
        }
    }

    /// Phím tắt mở bảng cài đặt giọng đọc
    private var settingsShortcutSection: some View {
        Button(action: {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ttsManager.showingSettingsSheet = true
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isEInkEnabled ? paperCanvas : Color.blue.opacity(0.12))
                        .frame(width: 36, height: 36)
                        .overlay { if isEInkEnabled { Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isEInkEnabled ? EInkPalette.ink : .blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cài đặt giọng đọc & Tốc độ")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                    Text("Tùy biến tốc độ, cao độ và chọn extension TTS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isEInkEnabled ? paperCard : Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay { if isEInkEnabled { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
            )
        }
        .buttonStyle(.plain)
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
