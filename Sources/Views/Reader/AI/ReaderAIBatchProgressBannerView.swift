import SwiftUI

/// Dải tiến độ quét tên riêng nhiều chương ở đầu màn AI (1.3.524).
///
/// - Đang chuẩn bị (chưa chia lượt): "Đang chuẩn bị quét tên riêng..." + "Đã đọc k/N chương" (báo sau mỗi khối
///   chương, 1.3.602).
/// - Đang gửi: "Batch N/T" với N là lượt **đang gửi** — khớp số tin gửi đi và dòng log `gửi lượt N/T`; dòng phụ
///   thêm số lượt lỗi đã bỏ qua khi có.
/// - Vòng thử lại lượt lỗi (tự động ở cuối lần quét hoặc nút "Thử lại k lượt lỗi", 1.3.527): "Đang thử lại: Batch i/k",
///   đếm trong số lượt đang thử lại.
/// - Chế độ AI của Google bị giới hạn số câu trả lời AI (1.3.612): đang chờ ⇒ nền cam, đồng hồ cát, đếm ngược từng giây
///   ("Google giới hạn câu trả lời AI — chờ 1:45"); đã chuyển sang Gemini Web ⇒ dòng phụ "Đã chuyển sang …".
public struct ReaderAIBatchProgressBannerView: View {
    public let progress: AINameScanProgress
    public let foundCount: Int
    public let onStop: () -> Void

    public init(progress: AINameScanProgress, foundCount: Int, onStop: @escaping () -> Void) {
        self.progress = progress
        self.foundCount = foundCount
        self.onStop = onStop
    }

    public var body: some View {
        HStack(spacing: 10) {
            if progress.rateLimitWaitUntil == nil {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "hourglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                if progress.rateLimitWaitUntil != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Google giới hạn câu trả lời AI — chờ \(GoogleAIModeError.clockText(seconds: progress.rateLimitRemainingSeconds(at: context.date) ?? 0))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                } else {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Dừng", action: onStop)
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(progress.rateLimitWaitUntil == nil ? Color.purple.opacity(0.12) : Color.orange.opacity(0.15))
    }

    private var title: String {
        if progress.isPreparing {
            return progress.isRetry ? "Đang chuẩn bị thử lại..." : "Đang chuẩn bị quét tên riêng..."
        }
        let verb = progress.isRetry ? "Đang thử lại" : "Đang quét tên riêng"
        return "\(verb): Batch \(progress.sendingBatch)/\(progress.totalBatches)..."
    }

    private var subtitle: String {
        if progress.isPreparing {
            if let count = progress.chapterCount {
                return "Đã đọc \(progress.preparedChapters)/\(count) chương"
            }
            return "Đang đọc chương đã tải"
        }
        if progress.rateLimitWaitUntil != nil {
            return "Batch \(progress.sendingBatch)/\(progress.totalBatches) · lần chờ \(progress.rateLimitWaitAttempt)/\(progress.rateLimitWaitTotal) · Đã tìm thấy \(foundCount) tên riêng"
        }
        let found = progress.switchedProviderName.map { "Đã chuyển sang \($0) (Chế độ AI bị giới hạn) · \(foundCount) tên" }
            ?? "Đã tìm thấy \(foundCount) tên riêng"
        return progress.failedBatches > 0 ? "\(found) · \(progress.failedBatches) lượt lỗi" : found
    }
}
