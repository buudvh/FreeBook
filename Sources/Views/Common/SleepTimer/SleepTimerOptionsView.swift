import SwiftUI
import UIKit

/// Phần **"Hẹn giờ tắt"** dùng chung: lưới mốc 15/30/45/60/90 phút + ô cuối (Hết chương / Hết tập / Hết bài) và khối
/// tuỳ chỉnh 1–180 phút. Tách nguyên văn từ tab "Hẹn giờ tắt" của `TTSQuickTimerSheet` — sheet TTS giữ đúng giao diện và
/// hành vi; phim / nhạc dùng trong `MediaSleepTimerSheet`.
///
/// View chỉ vẽ + gọi closure (rung + hiệu ứng lò xo như bản cũ); chỗ gọi quyết định hẹn giờ của ai. `customMinutes` là
/// binding để chỗ gọi tự giữ / tự gieo giá trị như trước.
struct SleepTimerOptionsView: View {
    /// Mốc phút đang hẹn; `nil` khi không hẹn theo phút.
    let selectedMinutes: Int?
    /// Nhãn + icon ô cuối của lưới.
    let endOfItemTitle: String
    let endOfItemIcon: String
    let isEndOfItemSelected: Bool
    @Binding var customMinutes: Double
    let onSelectMinutes: (Int) -> Void
    let onSelectEndOfItem: () -> Void

    static let presetMinutes = [15, 30, 45, 60, 90]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                presetGridSection
                customDurationSection
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    private var presetGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chọn nhanh mốc hẹn giờ")
                .font(.footnote).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Self.presetMinutes, id: \.self) { mins in
                    presetButton(title: "\(mins) phút", icon: "clock.fill", isSelected: selectedMinutes == mins) {
                        triggerHaptic()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { onSelectMinutes(mins) }
                    }
                }
                presetButton(title: endOfItemTitle, icon: endOfItemIcon, isSelected: isEndOfItemSelected) {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { onSelectEndOfItem() }
                }
            }
        }
    }

    private func presetButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16, weight: isSelected ? .bold : .regular)).foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(title).font(.subheadline).fontWeight(isSelected ? .bold : .medium).foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
            .shadow(color: isSelected ? Color.accentColor.opacity(0.1) : Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var customDurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tuỳ chỉnh thời gian")
                .font(.footnote).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)

            VStack(spacing: 14) {
                HStack {
                    Button(action: { triggerHaptic(); customMinutes = max(1, customMinutes - 1) }) {
                        Image(systemName: "minus.circle.fill").font(.system(size: 26)).foregroundStyle(Color.white)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("\(Int(customMinutes))").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(Color.primary)
                        Text("phút").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { triggerHaptic(); customMinutes = min(180, customMinutes + 1) }) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundStyle(Color.white)
                    }
                }
                .padding(.horizontal, 8)

                Slider(value: $customMinutes, in: 1...180, step: 1)

                Button(action: {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { onSelectMinutes(Int(customMinutes)) }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.caption.weight(.bold))
                        Text("Hẹn giờ \(Int(customMinutes)) phút").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                }
            }
            .padding(16).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        }
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
