import SwiftUI

struct ExtensionIconView: View {
    let localPath: String
    let iconUrl: String?
    let size: CGFloat
    
    var body: some View {
        if !localPath.isEmpty,
           let uiImage = UIImage(contentsOfFile: URL(fileURLWithPath: localPath).appendingPathComponent("icon.png").path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .cornerRadius(size * 0.18)
        } else if let iconUrl = iconUrl, let url = URL(string: iconUrl) {
            AsyncImage(url: url) { image in
                image.resizable()
            } placeholder: {
                fallbackIcon
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .cornerRadius(size * 0.18)
        } else {
            fallbackIcon
        }
    }
    
    private var fallbackIcon: some View {
        Image(systemName: "puzzlepiece.extension")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.7, height: size * 0.7)
            .padding(size * 0.15)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
            .cornerRadius(size * 0.18)
    }
}
