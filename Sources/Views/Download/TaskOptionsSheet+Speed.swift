import SwiftUI

/// Mục "Tốc độ tải" của `TaskOptionsSheet` (1.3.624): nghỉ giữa các lần tải (0–10 giây, bước 0,5) và số luồng (1–3).
///
/// - Giá trị đầu là bản đã lưu của nguồn (`DownloadSpeedSettings.load`). Bấm "Bắt đầu" thì ghi lại cho nguồn đó.
/// - Mặc định "Không" / 1 luồng là đúng cách tải trước đây.
/// - Truyện tranh chỉ có dòng nghỉ; nguồn Legado không có dòng số luồng (`supportsLanes`).
extension TaskOptionsSheet {
    /// Ẩn với video (tải tuần tự là chủ ý) và khi chỉ xuất chương đã tải (không phát request mạng nào).
    var showsSpeedSection: Bool {
        !isVideo && !(isExport && onlyExportCached)
    }

    var speedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Nghỉ giữa các lần tải")
                    Spacer()
                    Text(speed.delayTitle)
                        .font(.body.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: $speed.delaySeconds,
                    in: DownloadSpeedSettings.delayRange,
                    step: DownloadSpeedSettings.delayStep
                )
                .tint(.white)
            }
            .padding(.vertical, 4)

            if supportsLanes {
                Picker("Số luồng", selection: $speed.laneCount) {
                    ForEach(Array(DownloadSpeedSettings.laneRange), id: \.self) { count in
                        Text(count == 1 ? "1 (tuần tự)" : "\(count)").tag(count)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            helpHeader("Tốc độ tải", paragraphs: speedHelpParagraphs)
        }
    }
}
