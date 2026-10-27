import SwiftUI

/// Dòng URL xám nhỏ dưới câu lỗi: `SourceErrorLink.displayText` (host + path, không query), một dòng, cắt giữa nếu
/// dài. `link == nil` ⇒ không vẽ gì.
///
/// ```swift
/// Text(errorMessage).font(.subheadline).foregroundColor(.red)
/// ErrorLinkCaption(link: errorLink)
/// ```
struct ErrorLinkCaption: View {
    let link: SourceErrorLink?

    var body: some View {
        if let link {
            Text(link.displayText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("Link lỗi: \(link.displayText)")
        }
    }
}
