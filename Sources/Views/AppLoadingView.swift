import SwiftUI

struct AppLoadingView: View {
    @State private var pulseEffect = false
    
    var body: some View {
        ZStack {
            // Background với màu tối sang trọng hoặc đồng điệu với hệ thống
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer()
                
                // Icon biểu tượng ứng dụng với hiệu ứng Pulse nhẹ
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseEffect ? 1.06 : 0.96)
                        .animation(
                            .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                            value: pulseEffect
                        )
                    
                    Image(systemName: "book.closed.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .onAppear {
                    pulseEffect = true
                }
                
                // Tên ứng dụng và nhãn trạng thái
                VStack(spacing: 8) {
                    Text("FreeBook")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Đang chuẩn bị dữ liệu từ điển...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Vòng xoay ProgressView nhỏ gọn, tinh tế
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.2)
                    .tint(.blue)
                
                Spacer()
                
                // Chân trang hiển thị phiên bản
                Text("Phiên bản 1.0.0")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.6))
                    .padding(.bottom, 20)
            }
        }
    }
}

#Preview {
    AppLoadingView()
}
