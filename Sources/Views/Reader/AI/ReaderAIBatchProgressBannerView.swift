import SwiftUI

/// Dải tiến độ quét tên riêng nhiều chương ở đầu màn AI (1.3.524).
///
/// - Đang chuẩn bị (chưa chia lượt): "Đang chuẩn bị quét tên riêng..." + số chương đang đọc.
/// - Đang gửi: "Batch N/T" với N là lượt **đang gửi** — khớp số tin gửi đi và dòng log `gửi lượt N/T`; dòng phụ
///   thêm số lượt lỗi đã bỏ qua khi có.
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
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
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
        .background(Color.purple.opacity(0.12))
    }

    private var title: String {
        progress.isPreparing
            ? "Đang chuẩn bị quét tên riêng..."
            : "Đang quét tên riêng: Batch \(progress.sendingBatch)/\(progress.totalBatches)..."
    }

    private var subtitle: String {
        if progress.isPreparing {
            if let count = progress.chapterCount {
                return "Đang đọc \(count) chương đã tải"
            }
            return "Đang đọc chương đã tải"
        }
        let found = "Đã tìm thấy \(foundCount) tên riêng"
        return progress.failedBatches > 0 ? "\(found) · \(progress.failedBatches) lượt lỗi" : found
    }
}
