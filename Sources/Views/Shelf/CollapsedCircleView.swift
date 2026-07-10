import SwiftUI

struct CollapsedCircleView: View {
    let isPlaying: Bool
    let isHiddenMode: Bool
    let onTap: () -> Void
    
    private let size: CGFloat = 55
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.6))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 3)
            
            if isPlaying {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .offset(x: 1.5)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .opacity(isHiddenMode ? 0.4 : 1.0)
        .onTapGesture {
            onTap()
        }
    }
}
