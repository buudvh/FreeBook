import SwiftUI

struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat
    var color: Color = Color(.systemGray5)
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(width: width, height: height)
            .opacity(isAnimating ? 0.4 : 0.8)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}
