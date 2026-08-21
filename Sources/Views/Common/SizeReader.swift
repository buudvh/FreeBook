import SwiftUI

struct SizeReader: View {
    @Binding var size: CGSize

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    size = geometry.size
                }
                .onChange(of: geometry.size) { _, newValue in
                    size = newValue
                }
        }
    }
}
