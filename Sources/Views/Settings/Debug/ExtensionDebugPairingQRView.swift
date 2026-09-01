import CoreImage.CIFilterBuiltins
import SwiftUI

/// QR của pairing URI. Dựng bằng `CIFilter.qrCodeGenerator` nên không cần thêm dependency.
///
/// Nội dung QR **chứa token**, nên view này chỉ được dựng khi server đang chờ pair; chuỗi không bao giờ
/// đi qua `AppLogger` hay `ExtensionDebugEvent`.
struct ExtensionDebugPairingQRView: View {
    let content: String
    var side: CGFloat = 200

    var body: some View {
        if let image = Self.makeImage(from: content) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: side, height: side)
                .accessibilityLabel("Mã QR ghép nối debug")
        } else {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.secondary)
                .frame(width: side, height: side)
                .overlay(Text("Không dựng được QR").font(.caption))
        }
    }

    private static func makeImage(from content: String) -> UIImage? {
        guard !content.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Ảnh gốc chỉ vài chục pixel; scale bằng transform để không bị mờ khi hiển thị lớn.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
