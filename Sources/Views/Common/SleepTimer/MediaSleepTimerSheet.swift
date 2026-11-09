import SwiftUI
import UIKit

/// Sheet gọn **Hẹn giờ tắt** của trình phát phim và trình nghe nhạc: đầu sheet (tiêu đề, trạng thái đang hẹn, "Tắt hẹn
/// giờ" khi đang hẹn) + `SleepTimerOptionsView` (lưới mốc như sheet TTS, ô cuối "Hết tập" / "Hết bài"). Chọn mốc là áp ngay,
/// sheet vẫn mở (như sheet TTS); vuốt xuống để đóng — không có nút chỉ để đóng.
///
/// Mở từ màn trình bày bằng UIKit (màn xem phim, màn nghe) hoặc từ sheet nhạc của Reader ⇒ tự gắn
/// `.preferredColorScheme(.dark)` + `.appAccentTint()`. Chỉ view lá `StatusLine` đọc số giây.
struct MediaSleepTimerSheet: View {
    let timer: MediaSleepTimer

    @State private var customMinutes: Double = 90

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 14)
            SleepTimerOptionsView(
                selectedMinutes: timer.selectedMinutes,
                endOfItemTitle: timer.medium.endOfItemTitle,
                endOfItemIcon: timer.medium.endOfItemIcon,
                isEndOfItemSelected: timer.stopsAtEndOfItem,
                customMinutes: $customMinutes,
                onSelectMinutes: { timer.start(minutes: $0) },
                onSelectEndOfItem: { timer.setStopAtEndOfItem() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .appAccentTint()
        .presentationDetents([.fraction(0.64), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if let minutes = timer.selectedMinutes { customMinutes = Double(minutes) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hẹn giờ tắt")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                StatusLine(timer: timer)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if timer.isActive {
                Button("Tắt hẹn giờ", role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { timer.cancel() }
                }
                .headerTextButton()
            }
        }
    }

    // MARK: - Lồng (một type chính mỗi file)

    /// Dòng trạng thái dưới tiêu đề — view lá duy nhất của sheet đọc số giây còn lại.
    private struct StatusLine: View {
        let timer: MediaSleepTimer

        var body: some View {
            Text(text)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(timer.isActive ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }

        private var text: String {
            switch timer.mode {
            case .off:
                return "Chưa hẹn — chọn mốc để tự tạm dừng \(timer.medium.noun)"
            case .minutes(let minutes):
                guard timer.remainingSeconds > 0 else { return "\(minutes) phút · phát tiếp là đếm lại từ đầu" }
                return "Còn \(timer.badgeText) · chỉ đếm khi đang phát"
            case .endOfItem:
                return "Dừng khi \(timer.medium.endOfItemTitle.lowercased()), không sang mục kế"
            }
        }
    }
}
