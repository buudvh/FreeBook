import SwiftUI

/// Nội dung ngăn kéo `…` của màn nghe: thông tin album, mở trang nguồn, thêm bài đang phát vào playlist, công tắc tự phát
/// bài gợi ý, chọn nguồn lời
/// (≥ 2 nguồn), tốc độ phát, hẹn giờ tắt (mở `MediaSleepTimerSheet` của màn), dừng hẳn.
///
/// Ngăn kéo nằm ở cửa sổ nổi riêng (`SideDrawerMenuWindowManager`) ⇒ không thừa hưởng environment của màn: mọi giá trị và
/// hành động truyền vào từ màn (màn vẽ lại thì ngăn kéo nhận bản mới). Ngoại lệ: công tắc "Tự phát bài gợi ý" tự đọc
/// `@AppStorage` (không cần environment) — cùng khoá với Cài đặt › Đọc & Nghe › Âm thanh.
struct AudioPlayerDrawerMenu: View {
    /// Mặc định bật — khớp `AudioAutoNextPolicy.isEnabled`.
    @AppStorage(AudioAutoNextPolicy.defaultsKey) private var autoNextSuggest = AudioAutoNextPolicy.defaultValue

    let albumTitle: String
    let albumAuthor: String
    let sourceName: String
    let trackCount: Int
    let hasSourcePage: Bool
    /// Có bài đang phát / đang nạp ⇒ hiện hàng "Thêm bài này vào playlist".
    let hasCurrentTrack: Bool
    let lyricSources: [AudioLyricSource]
    let selectedLyricSourceId: Int?
    let playbackRate: Float
    /// `MediaSleepTimer.modeSummary` — chỉ theo chế độ, không đổi mỗi giây; `nil` = chưa hẹn.
    let sleepTimerSummary: String?
    let onOpenSourcePage: () -> Void
    let onAddToPlaylist: () -> Void
    let onSelectLyricSource: (AudioLyricSource) -> Void
    let onSelectRate: (Float) -> Void
    let onOpenSleepTimer: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SideDrawerSectionHeader("Thông tin album")
            albumInfo
            if hasSourcePage {
                SideDrawerActionRow("Mở trang nguồn", systemImage: "safari", action: onOpenSourcePage)
            }
            if hasCurrentTrack {
                SideDrawerActionRow("Thêm bài này vào playlist", systemImage: "text.badge.plus", action: onAddToPlaylist)
            }
            SideDrawerToggleRow("Tự phát bài gợi ý", systemImage: "forward.end.circle", isOn: $autoNextSuggest)
            if lyricSources.count >= 2 {
                SideDrawerSectionHeader("Nguồn lời")
                ForEach(lyricSources) { source in
                    SideDrawerOptionRow(source.displayLabel, isSelected: source.id == selectedLyricSourceId) {
                        onSelectLyricSource(source)
                    }
                }
            }
            SideDrawerSectionHeader("Tốc độ phát · \(AudioPlayerFormat.rate(playbackRate))")
            ForEach(AudioPlaybackSession.playbackRates, id: \.self) { rate in
                SideDrawerOptionRow(AudioPlayerFormat.rate(rate), isSelected: rate == playbackRate) {
                    onSelectRate(rate)
                }
            }
            SideDrawerDivider()
            SideDrawerActionRow("Hẹn giờ tắt", systemImage: "timer", detail: sleepTimerSummary ?? "Tắt", action: onOpenSleepTimer)
            SideDrawerActionRow("Dừng hẳn", systemImage: "stop.circle", role: .destructive, action: onStop)
        }
    }

    private var albumInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(albumTitle.isEmpty ? "Album" : albumTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
            if !albumAuthor.isEmpty {
                infoLine(label: "Tác giả", value: albumAuthor)
            }
            if !sourceName.isEmpty {
                infoLine(label: "Nguồn", value: sourceName)
            }
            if trackCount > 0 {
                infoLine(label: "Số bài", value: "\(trackCount)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func infoLine(label: String, value: String) -> some View {
        Text("\(label): \(value)")
            .font(.system(size: 13))
            .foregroundStyle(Color.white.opacity(0.7))
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
