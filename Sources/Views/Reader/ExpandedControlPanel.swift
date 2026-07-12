import SwiftUI

struct ExpandedControlPanel: View {
    let isPlaying: Bool
    let onBackToReader: () -> Void
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onShowSettings: () -> Void
    let onStop: () -> Void
    
    private let expandedWidth: CGFloat = 260
    
    var body: some View {
        HStack(spacing: 0) {
            // Nút Xem (Mở màn hình đọc truyện đang phát)
            Button(action: onBackToReader) {
                VStack(spacing: 2) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 16))
                    Text("Xem")
                        .font(.system(size: 8))
                }
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
            }
            
            Divider().frame(height: 24)
            
            // Nút Phát / Tạm dừng
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 44)
            }
            
            // Nút đọc đoạn tiếp theo (Skip Forward)
            Button(action: onSkipForward) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
                    .foregroundColor(isPlaying ? .primary : .secondary)
                    .frame(width: 48, height: 44)
            }
            .disabled(!isPlaying)
            
            // Nút Cài đặt đọc
            Button(action: onShowSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                    .frame(width: 48, height: 44)
            }
            
            Divider().frame(height: 24)
            
            // Nút X để dừng hẳn và tắt trình đọc nổi
            Button(action: onStop) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.red)
                    .frame(width: 44, height: 44)
            }
        }
        .frame(width: expandedWidth, height: 48)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}
