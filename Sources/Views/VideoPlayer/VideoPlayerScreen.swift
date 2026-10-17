import SwiftUI

/// Màn xem phim/video — **stub tạm** của Phần A (router đã trỏ tới đây). Phần C thay toàn bộ nội dung file.
struct VideoPlayerScreen: View {
    let launch: BookContentLaunch
    @Environment(\.dismiss) private var dismiss

    init(launch: BookContentLaunch) {
        self.launch = launch
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: ExtensionContentKind.video.symbolName)
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(.secondary)
            Text(launch.bookTitle ?? ExtensionContentKind.video.label)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("Đang phát triển")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Đóng")
            }
        }
    }
}
