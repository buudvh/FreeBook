import SwiftUI

extension BookDetailView {
    @ViewBuilder
    var customTabBar: some View {
        HStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = 0
                }
            }) {
                VStack(spacing: 8) {
                    Text("Chi tiết")
                        .font(.subheadline)
                        .fontWeight(selectedTab == 0 ? .bold : .medium)
                        .foregroundColor(selectedTab == 0 ? .accentColor : .secondary)

                    Rectangle()
                        .fill(selectedTab == 0 ? Color.accentColor : Color.clear)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = 1
                }
            }) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 8) {
                        Text("Mục lục")
                            .font(.subheadline)
                            .fontWeight(selectedTab == 1 ? .bold : .medium)
                            .foregroundColor(selectedTab == 1 ? .accentColor : .secondary)

                        Rectangle()
                            .fill(selectedTab == 1 ? Color.accentColor : Color.clear)
                            .frame(height: 3)
                    }

                    if newChapterBadgeCount > 0 {
                        Text(newChapterBadgeCount > 99 ? "99+" : "\(newChapterBadgeCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 10, y: -10)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .padding(.top, 4)
    }
}
